import AVKit
import PhotosUI
import SwiftUI

private enum PersistentTryOnPersonPage: Hashable {
    case photo(UUID)
    case add
}

private enum PersistentTryOnRailTab: String, CaseIterable, Identifiable {
    case pieces
    case shop

    var id: String { rawValue }
    var title: String { self == .pieces ? "Pieces" : "Shop" }
}

struct TryOnView: View {
    @Environment(AppModel.self) private var model

    @State private var personPickerItem: PhotosPickerItem?
    @State private var productPickerItem: PhotosPickerItem?
    @State private var wornReferencePickerItem: PhotosPickerItem?
    @State private var wornReferenceTargetID: UUID?
    @State private var selectedPersonPage: PersistentTryOnPersonPage = .add
    @State private var resultImages: [UUID: Data] = [:]
    @State private var resultJobIDs: [UUID: String] = [:]
    @State private var resultAppliedItemIDs: [UUID: Set<UUID>] = [:]
    @State private var resultGenders: [UUID: TryOnGender] = [:]
    @State private var savedJobIDs: Set<String> = []
    @State private var newCategory: TryOnCategory = .clothes
    @State private var isLibraryPresented = false
    @State private var isCameraPresented = false
    @State private var photoPendingDeletion: SavedTryOnPersonPhoto?
    @State private var confirmsPhotoDeletion = false
    @State private var isRailExpanded = true
    @State private var railTab: PersistentTryOnRailTab = .pieces
    @State private var fitCheckProduct: ProductResultDTO?

    @State private var isRendering = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var photoContext: TryOnPhotoContext = .outfit
    @State private var photoContextIsAutomatic = true
    @State private var gender: TryOnGender = .automatic
    @State private var acceptsUpload = false

    @State private var hasCredential = YouCamCredentialStore.isConfigured
    @State private var isCheckingConnection = false
    @State private var isConnectionVerified = false
    @State private var connectionError: String?

    @State private var renderTask: Task<Void, Never>?
    @State private var activeRenderID: UUID?
    @State private var isGeneratingVideo = false
    @State private var isShowingVideo = false
    @State private var videoStatus = ""
    @State private var videoURL: URL?
    @State private var videoSourceJobID: String?
    @State private var videoSourcePhotoID: UUID?
    @State private var videoSourceResolution: YouCamVideoResolution?
    @State private var videoResolution: YouCamVideoResolution = .p480
    @State private var removesBackground = false
    @State private var changesBackground = false
    @State private var backgroundPrompt = "Clean neutral editorial studio with soft natural shadows"
    @State private var improvesLighting = false
    @State private var enhancesPhoto = false
    @State private var activeVideoGenerationID: UUID?
    @State private var videoPlayer: AVPlayer?
    @State private var videoTask: Task<Void, Never>?
    @State private var playbackTask: Task<Void, Never>?

    private let service = YouCamTryOnService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                contextControls
                personStage
                tryOnRail
                credentialPanel
                controls
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(StylezamDesign.canvas)
        .navigationTitle("Try On")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hasCredential = YouCamCredentialStore.isConfigured
            syncPersonSelection(preferActive: true)
            applyAutomaticPhotoContextIfNeeded()
            await checkConnection()
        }
        .sheet(item: $fitCheckProduct) { product in
            ProductFitSheet(product: product)
        }
        .onChange(of: personPickerItem) { _, item in
            guard let item else { return }
            let targetContext = photoContext
            Task {
                if let data = await normalizedData(from: item) {
                    savePersonPhoto(data, for: targetContext)
                } else {
                    errorMessage = "That photo could not be read. Choose a JPEG, PNG, or HEIC image."
                }
                personPickerItem = nil
            }
        }
        .onChange(of: productPickerItem) { _, item in
            guard let item else { return }
            let targetCategory = newCategory
            Task {
                if let data = await normalizedData(from: item) {
                    do {
                        let saved = try model.library.addWardrobeItem(
                            title: targetCategory.title,
                            category: targetCategory,
                            imageData: data,
                            garmentRegion: .infer(category: targetCategory, title: targetCategory.title)
                        )
                        model.library.addWardrobeItemToTryOnRail(saved, selected: true)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } else {
                    errorMessage = "That product photo could not be prepared."
                }
                productPickerItem = nil
            }
        }
        .onChange(of: wornReferencePickerItem) { _, item in
            guard let item else { return }
            guard let targetID = wornReferenceTargetID else {
                wornReferencePickerItem = nil
                return
            }
            Task {
                if let data = await normalizedData(from: item) {
                    do {
                        guard try model.library.setLowerBodyTryOnReference(
                            for: targetID,
                            imageData: data
                        ) != nil else {
                            errorMessage = "That lower-body piece is no longer in your wardrobe."
                            wornReferencePickerItem = nil
                            wornReferenceTargetID = nil
                            return
                        }
                        status = "Worn reference ready"
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } else {
                    errorMessage = "That worn-garment photo could not be prepared."
                }
                wornReferencePickerItem = nil
                wornReferenceTargetID = nil
            }
        }
        .onChange(of: selectionSignature) { _, _ in
            applyAutomaticPhotoContextIfNeeded()
            invalidateAllResults()
            acceptsUpload = false
        }
        .onChange(of: gender) { _, _ in
            invalidateAllResults()
            acceptsUpload = false
        }
        .onChange(of: finishingOptions) { _, _ in
            invalidateAllResults()
            acceptsUpload = false
        }
        .onChange(of: videoResolution) { _, _ in
            cancelVideoWork(removeFile: true)
        }
        .onChange(of: model.library.tryOnPersonPhotos.map(\.id)) { _, _ in
            if activePhoto == nil {
                selectFirstPhoto(in: photoContext)
            }
        }
        .sheet(isPresented: $isLibraryPresented) {
            PersistentTryOnLibraryPicker()
                .environment(model)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            TryOnCameraCaptureView(context: photoContext) { data in
                savePersonPhoto(data, for: photoContext)
            }
        }
        .confirmationDialog(
            "Remove this photo?",
            isPresented: $confirmsPhotoDeletion,
            titleVisibility: .visible,
            presenting: photoPendingDeletion
        ) { photo in
            Button("Remove photo", role: .destructive) {
                deletePersonPhoto(photo)
            }
            Button("Cancel", role: .cancel) {
                photoPendingDeletion = nil
            }
        } message: { _ in
            Text("The original photo and its unsaved try-on result will be removed from this device.")
        }
        .onDisappear {
            cancelActiveRender()
            cancelVideoWork(removeFile: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            EditorialKicker(text: "YouCam photo try-on")
            Text("Build the look, piece by piece.")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1)
            Text("Saved pieces stay off until you choose Try On. Select one item or build a whole look, then create it in one action.")
                .foregroundStyle(.secondary)
        }
    }

    private var contextControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo target")
                        .font(.subheadline.weight(.semibold))
                    Text("Choose the area you want Stylezam to preserve.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button {
                    photoContextIsAutomatic = true
                    applyAutomaticPhotoContextIfNeeded()
                } label: {
                    Image(systemName: photoContextIsAutomatic ? "wand.and.stars.inverse" : "wand.and.stars")
                        .frame(width: 38, height: 38)
                }
                .stylezamGlassButton(prominent: photoContextIsAutomatic)
                .tint(StylezamDesign.cobalt)
                .accessibilityLabel("Choose photo type automatically from selected pieces")
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(TryOnPhotoContext.allCases) { context in
                    Button {
                        photoContextIsAutomatic = false
                        photoContext = context
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: context.symbol)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(context.shortTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(context.supportedPieces)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if photoContext == context {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline)
                            }
                        }
                        .foregroundStyle(
                            photoContext == context ? StylezamDesign.cobalt : Color.primary
                        )
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                        .background(
                            photoContext == context
                                ? StylezamDesign.cobalt.opacity(0.11)
                                : Color.secondary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(
                                    photoContext == context
                                        ? StylezamDesign.cobalt.opacity(0.7)
                                        : Color.primary.opacity(0.08),
                                    lineWidth: photoContext == context ? 1.25 : 0.75
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(context.title) photo for \(context.supportedPieces)")
                }
            }

            Label(
                photoContextIsAutomatic
                    ? "Stylezam chooses the correct photo target from the pieces selected on the rail."
                    : "Photo type is set manually. Tap the wand to use automatic selection.",
                systemImage: photoContextIsAutomatic ? "sparkles" : "hand.tap"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if photoContext == .outfit {
                Picker("Presentation", selection: $gender) {
                    ForEach(TryOnGender.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Text(
                    gender == .automatic
                        ? "Automatic is resolved once for this photo after you allow the upload. You can override it at any time."
                        : "This choice is sent only to YouCam features that require a presentation parameter."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(photoContext.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: photoContext) { _, context in
            invalidateAllResults()
            newCategory = context.categories.first ?? .clothes
            selectFirstPhoto(in: context)
            errorMessage = nil
            acceptsUpload = false
        }
    }

    private var personStage: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                TabView(selection: $selectedPersonPage) {
                    ForEach(contextPhotos) { photo in
                        personPhotoPage(photo)
                            .tag(PersistentTryOnPersonPage.photo(photo.id))
                    }

                    addPersonPhotoPage
                        .tag(PersistentTryOnPersonPage.add)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 410)
                .onChange(of: selectedPersonPage) { _, page in
                    cancelActiveRender()
                    cancelVideoWork(removeFile: true)
                    acceptsUpload = false
                    guard case let .photo(id) = page,
                          let photo = model.library.tryOnPersonPhotos.first(where: { $0.id == id })
                    else {
                        return
                    }
                    model.library.setActiveTryOnPhoto(photo)
                    errorMessage = nil
                }

                if let activePhoto {
                    Menu {
                        Button(role: .destructive) {
                            photoPendingDeletion = activePhoto
                            confirmsPhotoDeletion = true
                        } label: {
                            Label("Remove this photo", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                    }
                    .stylezamGlassButton()
                    .padding(10)
                    .accessibilityLabel("More actions for the current photo")
                }
            }

            HStack {
                Label(photoPositionLabel, systemImage: "photo.on.rectangle.angled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let activePhoto,
                   let jobID = resultJobIDs[activePhoto.id],
                   hasCachedVideo(photoID: activePhoto.id, jobID: jobID)
                {
                    Button {
                        playMotionPreview(photoID: activePhoto.id, jobID: jobID)
                    } label: {
                        Label("Replay", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Swipe for previous photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(StylezamDesign.hairline) }
    }

    @ViewBuilder
    private func personPhotoPage(_ photo: SavedTryOnPersonPhoto) -> some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)

            if isShowingVideo,
               activePhoto?.id == photo.id,
               videoSourcePhotoID == photo.id,
               videoSourceJobID == resultJobIDs[photo.id],
               let videoPlayer
            {
                VideoPlayer(player: videoPlayer)
                    .transition(.opacity)
                    .overlay(alignment: .topLeading) {
                        Label("3-second motion preview", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
            } else if let result = resultImages[photo.id] {
                DataImage(data: result, contentMode: .fit)
            } else {
                LocalFileImage(url: model.library.imageURL(for: photo), contentMode: .fit)
            }

            if isGeneratingVideo,
               activePhoto?.id == photo.id,
               videoSourcePhotoID == photo.id
            {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(videoStatus)
                        .font(.caption.weight(.semibold))
                }
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .clipped()
    }

    private var addPersonPhotoPage: some View {
        VStack(spacing: 14) {
            Image(systemName: photoContextSymbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(StylezamDesign.cobalt)
            Text(emptyPhotoTitle)
                .font(.title3.weight(.semibold))
            Text(photoContext.guidance)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 10) {
                Button {
                    isCameraPresented = true
                } label: {
                    Label("Take photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .stylezamGlassButton(prominent: true)
                .tint(StylezamDesign.cobalt)

                PhotosPicker(selection: $personPickerItem, matching: .images) {
                    Label("Photos", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .stylezamGlassButton()
            }
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tryOnRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(StylezamMotion.quickSpring) {
                    isRailExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TRY-ON RAIL")
                            .font(.caption2.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(StylezamDesign.cobalt)
                        Text(
                            "\(compatibleSelectedItems.count) this photo · "
                                + "\(parkedSelectedItems.count) parked · "
                                + "\(unselectedRailItems.count) off"
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: isRailExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isRailExpanded {
                HStack {
                    Picker("Rail view", selection: $railTab) {
                        ForEach(PersistentTryOnRailTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    addPieceMenu
                }

                if railTab == .pieces {
                    railPieces
                } else {
                    railShopping
                }
            }
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(StylezamDesign.hairline) }
    }

    private var addPieceMenu: some View {
        Menu {
            Menu("Product photo category") {
                Picker("Category", selection: $newCategory) {
                    ForEach(TryOnCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(category)
                    }
                }
            }
            PhotosPicker(selection: $productPickerItem, matching: .images) {
                Label("Add product photo", systemImage: "photo.badge.plus")
            }
            Button { isLibraryPresented = true } label: {
                Label("Add from Library", systemImage: "square.stack.3d.up")
            }
        } label: {
            Image(systemName: "plus")
                .frame(width: 38, height: 38)
        }
        .stylezamGlassButton()
        .accessibilityLabel("Add a piece to the try-on rail")
    }

    @ViewBuilder
    private var railPieces: some View {
        if tray.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your rail is empty")
                    .font(.subheadline.weight(.semibold))
                Text("Detect clothing from a reel or page, or use + to choose something from your Library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        } else {
            if !parkedSelectedItems.isEmpty {
                Label(
                    "\(parkedSelectedItems.count) selected \(parkedSelectedItems.count == 1 ? "piece is" : "pieces are") parked for another photo type.",
                    systemImage: "pause.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }

            if !selectedItemsMissingYouCamReference.isEmpty {
                Label(
                    "A selected lower-body piece needs a photo that clearly shows the garment being worn by one person. Add or replace the worn photo on its card before creating this look.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 142, maximum: 190), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(tray) { item in
                    trayCard(item)
                }
            }
        }
    }

    private func trayCard(_ item: TryOnTrayItem) -> some View {
        let isCompatible = isCompatibleWithCurrentPhoto(item)
        let isParked = item.isSelected && !isCompatible
        let isMissingReference = item.isSelected
            && isCompatible
            && !item.isYouCamReferenceReady

        return VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                Button {
                    model.library.setTryOnRailSelection(item.id, isSelected: !item.isSelected)
                } label: {
                    DataImage(data: item.imageData)
                        .frame(maxWidth: .infinity)
                        .frame(height: 154)
                        .clipped()
                        .opacity(item.isSelected ? (isCompatible ? 1 : 0.6) : 0.35)
                        .overlay(alignment: .bottomLeading) {
                            Image(
                                systemName: isMissingReference
                                    ? "exclamationmark.triangle.fill"
                                    : (isParked
                                        ? "pause.circle.fill"
                                        : (item.isSelected ? "checkmark.circle.fill" : "circle"))
                            )
                                .font(.title3)
                                .foregroundStyle(
                                    isMissingReference || isParked
                                        ? .orange
                                        : (item.isSelected ? StylezamDesign.cobalt : .secondary)
                                )
                                .padding(8)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isSelected ? "Deselect \(item.title)" : "Select \(item.title)")

                Button {
                    model.library.removeFromTryOnRail(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
                .accessibilityLabel("Remove \(item.title) from the rail")
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button {
                    model.library.setTryOnRailSelection(item.id, isSelected: !item.isSelected)
                } label: {
                    Text(item.isSelected ? "On" : "Off")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(item.isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            item.isSelected ? StylezamDesign.cobalt : Color(uiColor: .tertiarySystemFill),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isSelected ? "Deselect \(item.title)" : "Select \(item.title)")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.region.title)
                    .foregroundStyle(.secondary)
                Label(railStateLabel(for: item), systemImage: railStateSymbol(for: item))
                    .foregroundStyle(railStateColor(for: item))
            }
            .font(.caption2)

            if item.region == .lowerBody {
                Label(
                    item.isYouCamReferenceReady ? "Reference saved" : "Worn photo needed",
                    systemImage: item.isYouCamReferenceReady
                        ? "person.crop.rectangle.fill"
                        : "person.crop.rectangle.badge.plus"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.isYouCamReferenceReady ? StylezamDesign.cobalt : .orange)

                PhotosPicker(
                    selection: wornReferenceBinding(for: item.id),
                    matching: .images
                ) {
                    Text(item.isYouCamReferenceReady ? "Replace worn photo" : "Add worn photo")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    item.isYouCamReferenceReady
                        ? "Replace the worn reference photo for \(item.title)"
                        : "Add a worn reference photo for \(item.title)"
                )
            }

            if let product = item.sourceProduct {
                HStack(spacing: 10) {
                    Link(destination: product.productURL) {
                        Label(product.price?.formatted ?? "Shop", systemImage: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                    }
                    Button {
                        fitCheckProduct = product
                    } label: {
                        Label("Fit", systemImage: "ruler")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(StylezamDesign.cobalt)
                    .accessibilityLabel("Check how \(item.title) fits your measurements")
                }
            }
        }
        .padding(9)
        .background(
            Color(uiColor: .tertiarySystemBackground),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(item.isSelected ? StylezamDesign.cobalt.opacity(0.45) : StylezamDesign.hairline)
        }
    }

    @ViewBuilder
    private var railShopping: some View {
        if tray.compactMap(\.sourceProduct).isEmpty {
            Text("Purchase links appear here when a found or saved product is on the rail. Product photos you add yourself stay local-only references.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                shoppingGroup(title: "Selected for this photo", items: compatibleSelectedItems)
                shoppingGroup(title: "Selected · parked", items: parkedSelectedItems)
                shoppingGroup(title: "Off", items: unselectedRailItems)
            }
        }
    }

    @ViewBuilder
    private func shoppingGroup(title: String, items: [TryOnTrayItem]) -> some View {
        let shoppable = items.filter { $0.sourceProduct != nil }
        if !shoppable.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)

                ForEach(shoppable) { item in
                    if let product = item.sourceProduct {
                        HStack(spacing: 10) {
                            Link(destination: product.productURL) {
                                HStack(spacing: 10) {
                                    DataImage(data: item.imageData)
                                        .frame(width: 42, height: 50)
                                        .clipped()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(
                                            [product.merchant, product.price?.formatted]
                                                .compactMap { $0 }
                                                .joined(separator: " · ")
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                            }
                            Button {
                                fitCheckProduct = product
                            } label: {
                                Image(systemName: "ruler")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(StylezamDesign.cobalt)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        StylezamDesign.cobalt.opacity(0.09),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Check how \(item.title) fits your measurements")
                        }
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: readinessSymbol)
                    .foregroundStyle(isReadyToRender ? StylezamDesign.cobalt : .secondary)
                Text(readinessMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isReadyToRender ? .primary : .secondary)
            }

            if !compatibleSelectedItems.isEmpty {
                Label(
                    providerTaskSummary,
                    systemImage: "number.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            if !styledGeneratorSelectedItems.isEmpty {
                Label(
                    "\(styledGeneratorSelectedItems.map(\.category.title).joined(separator: ", ")) uses a Perfect Corp styled-preview task. Stylezam will keep the result only when your original person, clothing, and background remain unchanged outside the selected item.",
                    systemImage: "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if !parkedSelectedItems.isEmpty {
                Label(
                    "\(parkedSelectedItems.count) selected "
                        + "\(parkedSelectedItems.count == 1 ? "piece stays" : "pieces stay") parked and will not be uploaded.",
                    systemImage: "pause.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Try-on could not finish", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(errorMessage)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            if !compatibleLowerBodyItems.isEmpty {
                Label(
                    "For lower-body pieces, YouCam receives the full worn-reference photo—often the originating frame—not the crop shown on the rail. That frame may include people, surroundings, or page content. Continue only if it clearly shows the garment being worn by one person.",
                    systemImage: "photo.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            finishingControls

            Toggle("Allow this try-on upload", isOn: $acceptsUpload)
                .font(.subheadline)
                .disabled(
                    activePhoto == nil
                        || compatibleSelectedItems.isEmpty
                        || !selectedItemsMissingYouCamReference.isEmpty
                        || isRendering
                        || isGeneratingVideo
                )

            Button {
                startRender()
            } label: {
                HStack {
                    Text(
                        isRendering
                            ? status
                            : "Create look · \(totalProviderTaskCount) "
                                + "\(totalProviderTaskCount == 1 ? "task" : "tasks")"
                    )
                    Spacer()
                    if isRendering {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .stylezamGlassButton(prominent: true)
            .tint(StylezamDesign.cobalt)
            .disabled(!isReadyToRender || isRendering)

            if let activePhoto,
               let resultImage = resultImages[activePhoto.id],
               let jobID = resultJobIDs[activePhoto.id]
            {
                let hasCachedVideo = hasCachedVideo(photoID: activePhoto.id, jobID: jobID)
                Picker("Video quality", selection: $videoResolution) {
                    ForEach(YouCamVideoResolution.allCases) { resolution in
                        Text(resolution.title).tag(resolution)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isGeneratingVideo || isRendering)

                HStack(spacing: 10) {
                    Button {
                        viewAsVideo(
                            imageData: resultImage,
                            jobID: jobID,
                            photoID: activePhoto.id
                        )
                    } label: {
                        Label(
                            isGeneratingVideo
                                ? videoStatus
                                : (hasCachedVideo
                                    ? "Replay \(videoResolution.title)"
                                    : "Create \(videoResolution.title) video"),
                            systemImage: "play.rectangle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .stylezamGlassButton()
                    .disabled(
                        isGeneratingVideo
                            || isRendering
                            || (!hasCachedVideo && (!isConnectionVerified || !acceptsUpload))
                    )

                    Button {
                        saveCurrentLook(imageData: resultImage, jobID: jobID, photo: activePhoto)
                    } label: {
                        Label(
                            savedJobIDs.contains(jobID) ? "Saved" : "Save",
                            systemImage: savedJobIDs.contains(jobID) ? "bookmark.fill" : "bookmark"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .stylezamGlassButton()
                    .disabled(savedJobIDs.contains(jobID))
                }
            }

            Text("Each compatible selected piece is one YouCam try-on task. Video is a separate provider operation; 480p, 720p, and 1080p can have different unit costs. Uploaded and generated files may be retained by YouCam for up to 30 days. Previews show appearance, not physical size or fit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var finishingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish")
                        .font(.subheadline.weight(.semibold))
                    Text("Optional YouCam photo tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(finishingOptions.enabledTaskCount) on")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Toggle("Enhance detail", isOn: $enhancesPhoto)
            Toggle("Balance lighting", isOn: $improvesLighting)
            Toggle(
                "Remove background",
                isOn: Binding(
                    get: { removesBackground },
                    set: { enabled in
                        removesBackground = enabled
                        if enabled { changesBackground = false }
                    }
                )
            )
            Toggle(
                "Change background",
                isOn: Binding(
                    get: { changesBackground },
                    set: { enabled in
                        changesBackground = enabled
                        if enabled { removesBackground = false }
                    }
                )
            )

            if changesBackground {
                TextField("Background description", text: $backgroundPrompt, axis: .vertical)
                    .lineLimit(2...3)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Order: selected pieces, detail enhancement, lighting, then one background action. Every enabled finish is a separate provider task and may use additional YouCam units.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    @ViewBuilder
    private var credentialPanel: some View {
        if hasCredential {
            HStack(spacing: 10) {
                if isCheckingConnection {
                    ProgressView()
                } else {
                    Image(
                        systemName: isConnectionVerified
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isConnectionVerified ? StylezamDesign.cobalt : .orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isConnectionVerified ? "YouCam connected" : "YouCam needs attention")
                        .font(.subheadline.weight(.semibold))
                    if let connectionError {
                        Text(connectionError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer()

                if !isCheckingConnection, !isConnectionVerified {
                    Button("Retry") {
                        Task { await checkConnection() }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(12)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                EditorialSectionHeader(title: "YouCam unavailable", detail: "Build configuration")
                Label(
                    "This build was not provisioned with the virtual try-on service.",
                    systemImage: "key.slash"
                )
                .font(.subheadline)
                Text("Service credentials are managed by the developer build or credential gateway. Stylezam never asks a user to enter a provider key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tray: [TryOnTrayItem] {
        model.library.tryOnTrayItems()
    }

    private var selectedRailItems: [TryOnTrayItem] {
        tray.filter(\.isSelected).sorted { lhs, rhs in
            if lhs.region.renderPriority == rhs.region.renderPriority {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.region.renderPriority < rhs.region.renderPriority
        }
    }

    private var compatibleSelectedItems: [TryOnTrayItem] {
        selectedRailItems.filter(isCompatibleWithCurrentPhoto)
    }

    private var compatibleLowerBodyItems: [TryOnTrayItem] {
        compatibleSelectedItems.filter { $0.region == .lowerBody }
    }

    private var selectedItemsMissingYouCamReference: [TryOnTrayItem] {
        compatibleSelectedItems.filter { !$0.isYouCamReferenceReady }
    }

    private var parkedSelectedItems: [TryOnTrayItem] {
        selectedRailItems.filter { !isCompatibleWithCurrentPhoto($0) }
    }

    private var unselectedRailItems: [TryOnTrayItem] {
        tray.filter { !$0.isSelected }
    }

    private var contextPhotos: [SavedTryOnPersonPhoto] {
        model.library.tryOnPersonPhotos.filter { $0.context == photoContext }
    }

    private var activePhoto: SavedTryOnPersonPhoto? {
        guard case let .photo(id) = selectedPersonPage else { return nil }
        return model.library.tryOnPersonPhotos.first { $0.id == id }
    }

    private var isReadyToRender: Bool {
        activePhoto != nil
            && !compatibleSelectedItems.isEmpty
            && selectedItemsMissingYouCamReference.isEmpty
            && acceptsUpload
            && hasCredential
            && isConnectionVerified
    }

    private var readinessMessage: String {
        if activePhoto == nil { return "Take or choose your \(photoNoun) photo" }
        if selectedRailItems.isEmpty { return "Add or select at least one piece on the rail" }
        if compatibleSelectedItems.isEmpty {
            return "Selected pieces are parked—choose a compatible photo type"
        }
        if let missingReference = selectedItemsMissingYouCamReference.first {
            return "Add a worn-garment photo for \(missingReference.title)"
        }
        if !hasCredential { return "YouCam is not configured in this build" }
        if isCheckingConnection { return "Checking the YouCam connection" }
        if !isConnectionVerified { return "Retry the YouCam connection" }
        if !acceptsUpload { return "Allow this upload to continue" }
        return "Ready for \(totalProviderTaskCount) YouCam "
            + "\(totalProviderTaskCount == 1 ? "task" : "tasks")"
    }

    private var readinessSymbol: String {
        if isReadyToRender { return "checkmark.circle.fill" }
        if isCheckingConnection { return "clock" }
        return "circle.dashed"
    }

    private var finishingOptions: YouCamFinishingOptions {
        YouCamFinishingOptions(
            removesBackground: removesBackground,
            changesBackground: changesBackground,
            backgroundPrompt: backgroundPrompt,
            improvesLighting: improvesLighting,
            enhancesPhoto: enhancesPhoto
        )
    }

    private var totalProviderTaskCount: Int {
        compatibleSelectedItems.count + finishingOptions.enabledTaskCount
    }

    private var providerTaskSummary: String {
        let itemCount = compatibleSelectedItems.count
        let finishCount = finishingOptions.enabledTaskCount
        var summary = "Create will run exactly \(totalProviderTaskCount) YouCam "
            + "\(totalProviderTaskCount == 1 ? "task" : "tasks") for this photo: "
            + "\(itemCount) selected \(itemCount == 1 ? "item" : "items")"
        if finishCount > 0 {
            summary += " + \(finishCount) finish \(finishCount == 1 ? "action" : "actions")"
        }
        return summary + "."
    }

    private var styledGeneratorSelectedItems: [TryOnTrayItem] {
        compatibleSelectedItems.filter {
            [.bag, .scarf, .shoes, .hat].contains($0.category)
        }
    }

    private var selectionSignature: String {
        tray.map {
            "\($0.id.uuidString):\($0.category.rawValue):\($0.region.rawValue):"
                + "\($0.contentDigest ?? ""):\($0.referenceContentDigest ?? ""):\($0.isSelected)"
        }
        .joined(separator: "|")
    }

    private func applyAutomaticPhotoContextIfNeeded() {
        guard photoContextIsAutomatic,
              let suggested = suggestedPhotoContext
        else { return }
        guard suggested != photoContext else { return }
        photoContext = suggested
    }

    /// Chooses the photo view that can render the greatest number of selected
    /// pieces. A tie keeps the current view so a mixed rail does not jump while
    /// the user is composing it. With one selected piece, jewelry routes to the
    /// required close-up automatically and everything else routes to Outfit.
    private var suggestedPhotoContext: TryOnPhotoContext? {
        guard !selectedRailItems.isEmpty else { return nil }
        if selectedRailItems.count == 1, let item = selectedRailItems.first {
            switch item.category {
            case .ring, .bracelet, .watch:
                return .handAndWrist
            case .hat:
                return .head
            case .scarf, .earring, .necklace:
                return .faceAndNeck
            default:
                return .outfit
            }
        }

        let scores = TryOnPhotoContext.allCases.map { context in
            (context, selectedRailItems.filter { context.renderCategories.contains($0.category) }.count)
        }
        guard let bestScore = scores.map(\.1).max(), bestScore > 0 else { return nil }
        let best = scores.filter { $0.1 == bestScore }.map(\.0)
        return best.contains(photoContext) ? photoContext : best.first
    }

    private func isCompatibleWithCurrentPhoto(_ item: TryOnTrayItem) -> Bool {
        return photoContext.renderCategories.contains(item.category)
    }

    private func wornReferenceBinding(for itemID: UUID) -> Binding<PhotosPickerItem?> {
        Binding(
            get: {
                wornReferenceTargetID == itemID ? wornReferencePickerItem : nil
            },
            set: { newValue in
                wornReferenceTargetID = itemID
                wornReferencePickerItem = newValue
            }
        )
    }

    private func railStateLabel(for item: TryOnTrayItem) -> String {
        guard item.isSelected else { return "Off" }
        if isCompatibleWithCurrentPhoto(item), !item.isYouCamReferenceReady {
            return "Needs worn photo"
        }
        guard !isCompatibleWithCurrentPhoto(item) else {
            return "For \(photoContext.title)"
        }
        let destination = TryOnPhotoContext.allCases.first {
            $0.renderCategories.contains(item.category)
        }
        return "Parked · \(destination?.title ?? "other photo")"
    }

    private func railStateSymbol(for item: TryOnTrayItem) -> String {
        guard item.isSelected else { return "circle" }
        if isCompatibleWithCurrentPhoto(item), !item.isYouCamReferenceReady {
            return "exclamationmark.triangle.fill"
        }
        return isCompatibleWithCurrentPhoto(item) ? "checkmark.circle.fill" : "pause.circle.fill"
    }

    private func railStateColor(for item: TryOnTrayItem) -> Color {
        guard item.isSelected else { return .secondary }
        if isCompatibleWithCurrentPhoto(item), !item.isYouCamReferenceReady {
            return .orange
        }
        return isCompatibleWithCurrentPhoto(item) ? StylezamDesign.cobalt : .orange
    }

    private var photoPositionLabel: String {
        guard let activePhoto,
              let index = contextPhotos.firstIndex(where: { $0.id == activePhoto.id })
        else { return "Add a photo" }
        return "Photo \(index + 1) of \(contextPhotos.count)"
    }

    private var photoNoun: String {
        switch photoContext {
        case .outfit: "outfit"
        case .head: "hat"
        case .handAndWrist: "hand or wrist"
        case .faceAndNeck: "face and neck"
        }
    }

    private var emptyPhotoTitle: String {
        switch photoContext {
        case .outfit: "Take a photo of yourself"
        case .head: "Take a head photo for a hat"
        case .handAndWrist: "Take a hand or wrist photo"
        case .faceAndNeck: "Take a face and neck photo"
        }
    }

    private var photoContextSymbol: String {
        switch photoContext {
        case .outfit: "person.crop.rectangle.badge.plus"
        case .head: "baseball.cap"
        case .handAndWrist: "hand.raised"
        case .faceAndNeck: "person.crop.square"
        }
    }

    private func startRender() {
        guard let activePhoto else { return }

        let selected = compatibleSelectedItems
        guard selectedItemsMissingYouCamReference.isEmpty else {
            errorMessage = "Add a photo that shows each selected lower-body piece worn by one person before creating this look."
            return
        }
        errorMessage = nil
        resultImages[activePhoto.id] = nil
        resultJobIDs[activePhoto.id] = nil
        resultAppliedItemIDs[activePhoto.id] = nil
        cancelVideoWork(removeFile: true)
        isRendering = true

        let renderingPhotoID = activePhoto.id
        let personImageURL = model.library.imageURL(for: activePhoto)
        let renderID = UUID()
        activeRenderID = renderID
        renderTask = Task {
            do {
                status = "Preparing your photo"
                let personImage = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: personImageURL, options: .mappedIfSafe)
                }.value
                try Task.checkCancellation()
                let categoriesNeedingPresentation: Set<TryOnCategory> = [
                    .bag, .scarf, .shoes, .hat,
                ]
                let resolvedGender: TryOnGender
                if selected.contains(where: { categoriesNeedingPresentation.contains($0.category) }) {
                    status = "Matching the photo presentation"
                    resolvedGender = try await model.resolvedTryOnGender(
                        for: activePhoto,
                        imageData: personImage,
                        preference: gender
                    )
                } else {
                    // Clothes and jewelry endpoints do not consume this parameter.
                    resolvedGender = gender.isProviderValue ? gender : .male
                }
                let output = try await service.render(
                    personImage: personImage,
                    items: selected,
                    gender: resolvedGender,
                    finishing: finishingOptions
                ) { current, total, label in
                    await MainActor.run {
                        status = current == total ? label : "\(label) · \(current + 1)/\(total)"
                    }
                }
                guard activeRenderID == renderID, !Task.isCancelled else { return }
                resultImages[renderingPhotoID] = output.imageData
                resultJobIDs[renderingPhotoID] = output.jobID
                resultAppliedItemIDs[renderingPhotoID] = Set(selected.map(\.id))
                resultGenders[renderingPhotoID] = resolvedGender
            } catch is CancellationError {
            } catch {
                if activeRenderID == renderID {
                    errorMessage = error.localizedDescription
                }
            }

            if activeRenderID == renderID {
                isRendering = false
                activeRenderID = nil
                renderTask = nil
            }
        }
    }

    private func saveCurrentLook(
        imageData: Data,
        jobID: String,
        photo: SavedTryOnPersonPhoto
    ) {
        let appliedIDs = resultAppliedItemIDs[photo.id] ?? []
        let appliedItems = tray.filter { appliedIDs.contains($0.id) }
        do {
            _ = try model.library.addTryOn(
                jobID: jobID,
                title: appliedItems.map(\.title).joined(separator: " + "),
                personPhotoID: photo.id,
                photoContext: photo.context,
                gender: resultGenders[photo.id],
                items: model.library.tryOnItemSnapshots(appliedItemIDs: appliedIDs),
                imageData: imageData
            )
            status = "Saved to past try-ons"
            savedJobIDs.insert(jobID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func viewAsVideo(imageData: Data, jobID: String, photoID: UUID) {
        errorMessage = nil
        guard activePhoto?.id == photoID,
              resultJobIDs[photoID] == jobID
        else { return }

        if videoSourcePhotoID == photoID,
           videoSourceJobID == jobID,
           videoURL != nil
        {
            playMotionPreview(photoID: photoID, jobID: jobID)
            return
        }

        cancelVideoWork(removeFile: true)
        let generationID = UUID()
        activeVideoGenerationID = generationID
        videoSourcePhotoID = photoID
        videoSourceJobID = jobID
        videoSourceResolution = videoResolution
        isGeneratingVideo = true
        videoStatus = "Preparing motion preview"
        videoTask = Task {
            do {
                let requestedResolution = videoResolution
                let output = try await service.animate(
                    imageData: imageData,
                    resolution: requestedResolution
                ) { message in
                    await MainActor.run {
                        guard activeVideoGenerationID == generationID,
                              videoSourcePhotoID == photoID,
                              videoSourceJobID == jobID
                        else { return }
                        videoStatus = message
                    }
                }
                guard !Task.isCancelled,
                      activeVideoGenerationID == generationID,
                      activePhoto?.id == photoID,
                      resultJobIDs[photoID] == jobID,
                      videoSourcePhotoID == photoID,
                      videoSourceJobID == jobID
                else {
                    resetVideoGenerationIfCurrent(generationID)
                    return
                }

                let destination = FileManager.default.temporaryDirectory
                    .appending(path: "stylezam-motion-\(UUID().uuidString).mp4")
                try await Task.detached(priority: .utility) {
                    try output.videoData.write(to: destination, options: .atomic)
                }.value

                guard !Task.isCancelled,
                      activeVideoGenerationID == generationID,
                      activePhoto?.id == photoID,
                      resultJobIDs[photoID] == jobID,
                      videoSourcePhotoID == photoID,
                      videoSourceJobID == jobID
                else {
                    try? FileManager.default.removeItem(at: destination)
                    resetVideoGenerationIfCurrent(generationID)
                    return
                }

                videoURL = destination
                isGeneratingVideo = false
                activeVideoGenerationID = nil
                videoTask = nil
                playMotionPreview(photoID: photoID, jobID: jobID)
            } catch is CancellationError {
                resetVideoGenerationIfCurrent(generationID)
            } catch {
                if activeVideoGenerationID == generationID {
                    resetVideoGenerationIfCurrent(generationID)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func hasCachedVideo(photoID: UUID, jobID: String) -> Bool {
        videoSourcePhotoID == photoID
            && videoSourceJobID == jobID
            && videoSourceResolution == videoResolution
            && videoURL != nil
    }

    private func playMotionPreview(photoID: UUID, jobID: String) {
        guard activePhoto?.id == photoID,
              resultJobIDs[photoID] == jobID,
              videoSourcePhotoID == photoID,
              videoSourceJobID == jobID,
              let videoURL
        else { return }
        playbackTask?.cancel()
        let player = AVPlayer(url: videoURL)
        videoPlayer = player
        isShowingVideo = true
        player.play()
        playbackTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            player.pause()
            isShowingVideo = false
            videoPlayer = nil
            playbackTask = nil
        }
    }

    private func cancelVideoWork(removeFile: Bool) {
        videoTask?.cancel()
        videoTask = nil
        activeVideoGenerationID = nil
        isGeneratingVideo = false
        videoStatus = ""
        endVideoPlayback(removeFile: removeFile)
    }

    private func resetVideoGenerationIfCurrent(_ generationID: UUID) {
        guard activeVideoGenerationID == generationID else { return }
        videoTask = nil
        activeVideoGenerationID = nil
        isGeneratingVideo = false
        videoStatus = ""
        removeTemporaryVideo()
    }

    private func endVideoPlayback(removeFile: Bool) {
        playbackTask?.cancel()
        playbackTask = nil
        videoPlayer?.pause()
        videoPlayer = nil
        isShowingVideo = false
        if removeFile { removeTemporaryVideo() }
    }

    private func removeTemporaryVideo() {
        if let videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        videoURL = nil
        videoSourceJobID = nil
        videoSourcePhotoID = nil
        videoSourceResolution = nil
    }

    private func invalidateAllResults() {
        cancelActiveRender()
        resultImages.removeAll()
        resultJobIDs.removeAll()
        resultAppliedItemIDs.removeAll()
        resultGenders.removeAll()
        savedJobIDs.removeAll()
        cancelVideoWork(removeFile: true)
    }

    private func cancelActiveRender() {
        renderTask?.cancel()
        renderTask = nil
        activeRenderID = nil
        isRendering = false
    }

    private func normalizedData(from item: PhotosPickerItem) async -> Data? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await ImageEncoding.normalizedJPEGAsync(from: data)
    }

    private func savePersonPhoto(_ data: Data, for context: TryOnPhotoContext) {
        cancelActiveRender()
        cancelVideoWork(removeFile: true)
        do {
            let photo = try model.library.addTryOnPersonPhoto(imageData: data, context: context)
            photoContext = context
            selectedPersonPage = .photo(photo.id)
            resultImages[photo.id] = nil
            resultJobIDs[photo.id] = nil
            resultAppliedItemIDs[photo.id] = nil
            acceptsUpload = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePersonPhoto(_ photo: SavedTryOnPersonPhoto) {
        let context = photoContext
        photoPendingDeletion = nil
        cancelVideoWork(removeFile: true)
        resultImages[photo.id] = nil
        resultJobIDs[photo.id] = nil
        resultAppliedItemIDs[photo.id] = nil
        model.library.deleteTryOnPersonPhoto(photo)
        selectFirstPhoto(in: context)
    }

    private func syncPersonSelection(preferActive: Bool) {
        if preferActive, let photo = model.library.activeTryOnPhoto {
            photoContext = photo.context
            selectedPersonPage = .photo(photo.id)
        } else {
            selectFirstPhoto(in: photoContext)
        }
    }

    private func selectFirstPhoto(in context: TryOnPhotoContext) {
        if let photo = model.library.tryOnPersonPhotos.first(where: { $0.context == context }) {
            selectedPersonPage = .photo(photo.id)
            model.library.setActiveTryOnPhoto(photo)
        } else {
            selectedPersonPage = .add
        }
    }

    @MainActor
    private func checkConnection() async {
        guard YouCamCredentialStore.isConfigured else {
            hasCredential = false
            isConnectionVerified = false
            connectionError = nil
            return
        }
        hasCredential = true
        isCheckingConnection = true
        connectionError = nil
        do {
            try await service.validateConnection()
            isConnectionVerified = true
        } catch {
            isConnectionVerified = false
            connectionError = error.localizedDescription
        }
        isCheckingConnection = false
    }
}

private struct PersistentTryOnLibraryRowFeedback {
    let message: String
    let isError: Bool
}

private struct PersistentTryOnLibraryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rowFeedback: [String: PersistentTryOnLibraryRowFeedback] = [:]
    @State private var busyProductIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if !model.library.wardrobeItems.isEmpty {
                    Section("Clothes library") {
                        ForEach(model.library.wardrobeItems) { item in
                            Button {
                                model.library.addWardrobeItemToTryOnRail(item, selected: true)
                            } label: {
                                HStack(spacing: 12) {
                                    LocalFileImage(
                                        url: model.library.imageURL(for: item),
                                        contentMode: .fit
                                    )
                                    .frame(width: 54, height: 64)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .foregroundStyle(.primary)
                                        Text(item.category.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(
                                        systemName: railIDs.contains(item.id)
                                            ? "checkmark.circle.fill"
                                            : "plus.circle"
                                    )
                                    .foregroundStyle(StylezamDesign.cobalt)
                                }
                            }
                        }
                    }
                }

                if !model.library.products.isEmpty {
                    Section("Saved products") {
                        ForEach(model.library.products) { saved in
                            let rowKey = productRowKey(saved.product)
                            let railEntry = productRailEntry(for: saved.product)
                            Button {
                                Task { await addProduct(saved.product, rowKey: rowKey) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 12) {
                                        ProductImage(url: saved.product.imageURL)
                                            .frame(width: 54, height: 64)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(saved.product.title)
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                            Text(saved.product.merchant)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if busyProductIDs.contains(saved.id) {
                                            ProgressView()
                                        } else {
                                            Image(systemName: railMembershipSymbol(for: railEntry))
                                                .foregroundStyle(StylezamDesign.cobalt)
                                        }
                                    }

                                    if let feedback = rowFeedback[rowKey] {
                                        Text(feedback.message)
                                            .font(.caption2)
                                            .foregroundStyle(feedback.isError ? Color.red : Color.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .disabled(
                                busyProductIDs.contains(saved.id)
                                    || railEntry?.isSelected == true
                            )
                        }
                    }
                }

                ForEach(model.library.scans) { scan in
                    let available = scan.items.filter(\.accepted)
                    if !available.isEmpty {
                        Section(scan.createdAt.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(available) { garment in
                                if let url = model.library.cropURL(for: garment) {
                                    let rowKey = scanRowKey(scanID: scan.id, garmentID: garment.id)
                                    let railEntry = scanRailEntry(
                                        scanID: scan.id,
                                        garmentID: garment.id
                                    )
                                    Button {
                                        addScanCrop(
                                            scanID: scan.id,
                                            garmentID: garment.id,
                                            title: garment.title,
                                            rowKey: rowKey
                                        )
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack(spacing: 12) {
                                                LocalFileImage(url: url, contentMode: .fit)
                                                    .frame(width: 54, height: 64)
                                                Text(garment.title)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                Image(systemName: railMembershipSymbol(for: railEntry))
                                                    .foregroundStyle(StylezamDesign.cobalt)
                                            }

                                            if let feedback = rowFeedback[rowKey] {
                                                Text(feedback.message)
                                                    .font(.caption2)
                                                    .foregroundStyle(
                                                        feedback.isError ? Color.red : Color.secondary
                                                    )
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                    .disabled(railEntry?.isSelected == true)
                                }
                            }
                        }
                    }
                }

                if model.library.scans.isEmpty,
                   model.library.products.isEmpty,
                   model.library.wardrobeItems.isEmpty
                {
                    ContentUnavailableView(
                        "No pieces yet",
                        systemImage: "tshirt",
                        description: Text("Detect a look first, or add a product photo from the try-on rail.")
                    )
                }

            }
            .navigationTitle("Add from Library")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var railIDs: Set<UUID> {
        Set(model.library.tryOnRail.map(\.wardrobeItemID))
    }

    private func productRowKey(_ product: ProductResultDTO) -> String {
        "product:\(product.id)"
    }

    private func scanRowKey(scanID: UUID, garmentID: String) -> String {
        "scan:\(scanID.uuidString):\(garmentID)"
    }

    private func preferredWardrobeItem(for product: ProductResultDTO) -> SavedWardrobeItem? {
        let matches = model.library.wardrobeItems.filter { $0.sourceProduct?.id == product.id }
        let selectedIDs = Set(
            model.library.tryOnRail.filter(\.isSelected).map(\.wardrobeItemID)
        )
        let onRailIDs = Set(model.library.tryOnRail.map(\.wardrobeItemID))
        return matches.first(where: { selectedIDs.contains($0.id) })
            ?? matches.first(where: { onRailIDs.contains($0.id) })
            ?? matches.first
    }

    private func productRailEntry(for product: ProductResultDTO) -> TryOnRailEntry? {
        guard let item = preferredWardrobeItem(for: product) else { return nil }
        return model.library.tryOnRail.first { $0.wardrobeItemID == item.id }
    }

    private func scanWardrobeItem(scanID: UUID, garmentID: String) -> SavedWardrobeItem? {
        model.library.wardrobeItems.first {
            $0.sourceScanID == scanID && $0.sourceGarmentID == garmentID
        }
    }

    private func scanRailEntry(scanID: UUID, garmentID: String) -> TryOnRailEntry? {
        guard let item = scanWardrobeItem(scanID: scanID, garmentID: garmentID) else {
            return nil
        }
        return model.library.tryOnRail.first { $0.wardrobeItemID == item.id }
    }

    private func railMembershipSymbol(for entry: TryOnRailEntry?) -> String {
        guard let entry else { return "plus.circle" }
        return entry.isSelected ? "checkmark.circle.fill" : "checkmark.circle"
    }

    private func isSelectedOnRail(_ itemID: UUID) -> Bool {
        model.library.tryOnRail.first { $0.wardrobeItemID == itemID }?.isSelected == true
    }

    private func setFeedback(_ message: String, isError: Bool, rowKey: String) {
        rowFeedback[rowKey] = PersistentTryOnLibraryRowFeedback(
            message: message,
            isError: isError
        )
    }

    private func addScanCrop(
        scanID: UUID,
        garmentID: String,
        title: String,
        rowKey: String
    ) {
        rowFeedback[rowKey] = nil
        do {
            guard let item = try model.library.addDetectedGarmentToTryOnRail(
                scanID: scanID,
                garmentID: garmentID
            ) else {
                setFeedback(
                    "This saved crop is no longer available.",
                    isError: true,
                    rowKey: rowKey
                )
                return
            }
            guard isSelectedOnRail(item.id) else {
                setFeedback(
                    model.library.loadError ?? "This crop could not be selected on the try-on rail.",
                    isError: true,
                    rowKey: rowKey
                )
                return
            }
            setFeedback("\(title) is selected on the try-on rail.", isError: false, rowKey: rowKey)
        } catch {
            setFeedback(error.localizedDescription, isError: true, rowKey: rowKey)
        }
    }

    @MainActor
    private func addProduct(_ product: ProductResultDTO, rowKey: String) async {
        guard !busyProductIDs.contains(product.id) else { return }
        rowFeedback[rowKey] = nil

        if let existing = preferredWardrobeItem(for: product) {
            model.library.addWardrobeItemToTryOnRail(existing, selected: true)
            if isSelectedOnRail(existing.id) {
                setFeedback("Selected on the try-on rail.", isError: false, rowKey: rowKey)
            } else {
                setFeedback(
                    model.library.loadError ?? "This product could not be selected on the try-on rail.",
                    isError: true,
                    rowKey: rowKey
                )
            }
            return
        }

        guard let url = product.imageURL else {
            setFeedback(
                "This saved product has no usable image.",
                isError: true,
                rowKey: rowKey
            )
            return
        }

        busyProductIDs.insert(product.id)
        defer { busyProductIDs.remove(product.id) }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue(
                "image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count < 25_000_000,
                  let normalized = await ImageEncoding.normalizedJPEGAsync(from: data)
            else {
                setFeedback(
                    "The saved product image could not be prepared.",
                    isError: true,
                    rowKey: rowKey
                )
                return
            }
            let item = try model.library.upsertProductInTryOnRail(product, imageData: normalized)
            guard isSelectedOnRail(item.id) else {
                setFeedback(
                    model.library.loadError ?? "This product could not be selected on the try-on rail.",
                    isError: true,
                    rowKey: rowKey
                )
                return
            }
            setFeedback("Selected on the try-on rail.", isError: false, rowKey: rowKey)
        } catch {
            setFeedback(error.localizedDescription, isError: true, rowKey: rowKey)
        }
    }
}
