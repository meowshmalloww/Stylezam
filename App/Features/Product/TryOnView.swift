import AVFoundation
import PhotosUI
import SwiftUI

struct TryOnView: View {
    @Environment(AppModel.self) private var model
    @State private var personPickerItem: PhotosPickerItem?
    @State private var productPickerItem: PhotosPickerItem?
    @State private var personImages: [TryOnPhotoContext: Data] = [:]
    @State private var resultImages: [TryOnPhotoContext: Data] = [:]
    @State private var resultJobIDs: [TryOnPhotoContext: String] = [:]
    @State private var savedJobIDs: Set<String> = []
    @State private var tray: [TryOnTrayItem] = []
    @State private var newCategory: TryOnCategory = .clothes
    @State private var isLibraryPresented = false
    @State private var isCameraPresented = false
    @State private var isLoadingFoundProducts = false
    @State private var foundProductStatus: String?
    @State private var isRendering = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var photoContext: TryOnPhotoContext = .outfit
    @State private var gender: TryOnGender = .female
    @State private var acceptsRetention = false
    @State private var credential = ""
    @State private var hasCredential = YouCamCredentialStore.isConfigured
    @State private var isCheckingConnection = false
    @State private var isConnectionVerified = false
    @State private var connectionError: String?
    @State private var renderTask: Task<Void, Never>?
    @State private var activeRenderID: UUID?
    @State private var activeRenderContext: TryOnPhotoContext?
    private let service = YouCamTryOnService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                contextControls
                personStage
                itemTray
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
            await checkConnection()
        }
        .onChange(of: personPickerItem) { _, item in
            guard let item else { return }
            let targetContext = photoContext
            Task {
                if let data = await normalizedData(from: item) {
                    setPersonPhoto(data, for: targetContext)
                } else {
                    errorMessage = "That photo could not be read. Choose a JPEG, PNG, or HEIC image."
                }
                personPickerItem = nil
            }
        }
        .onChange(of: productPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = await normalizedData(from: item) {
                    appendTrayItem(TryOnTrayItem(title: newCategory.title, category: newCategory, imageData: data))
                }
                productPickerItem = nil
            }
        }
        .onChange(of: selectionSignature) { _, _ in
            invalidateResult(for: photoContext)
            acceptsRetention = false
        }
        .task(id: model.pendingTryOnProducts.map(\.id)) {
            let pending = model.pendingTryOnProducts
            guard !pending.isEmpty else { return }
            isLoadingFoundProducts = true
            for product in pending where !tray.contains(where: { $0.sourceProduct?.id == product.id }) {
                foundProductStatus = "Adding \(product.title)"
                await addPendingProduct(product)
            }
            let handledIDs = Set(pending.map(\.id))
            model.pendingTryOnProducts.removeAll { product in
                handledIDs.contains(product.id)
            }
            isLoadingFoundProducts = false
            if !tray.isEmpty { foundProductStatus = "Found piece ready" }
        }
        .task(id: model.pendingTryOnItems.map(\.id)) {
            let pending = model.pendingTryOnItems
            guard !pending.isEmpty else { return }
            for item in pending {
                appendTrayItem(item)
            }
            let handledIDs = Set(pending.map(\.id))
            model.pendingTryOnItems.removeAll { handledIDs.contains($0.id) }
            foundProductStatus = pending.count == 1
                ? "Detected crop ready"
                : "\(pending.count) detected crops ready"
        }
        .sheet(isPresented: $isLibraryPresented) {
            TryOnLibraryPicker { item in
                appendTrayItem(item)
            }
                .environment(model)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            TryOnCameraCaptureView(context: photoContext) { data in
                setPersonPhoto(data, for: photoContext)
            }
        }
        .onDisappear { renderTask?.cancel() }
    }

    private var contextControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Photo type", selection: $photoContext) {
                ForEach(TryOnPhotoContext.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if photoContext == .outfit {
                Picker("Presentation", selection: $gender) {
                    ForEach(TryOnGender.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Text(photoContext.guidance).font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: photoContext) { _, context in
            if let activeRenderContext, activeRenderContext != context {
                cancelActiveRender()
            }
            newCategory = context.categories[0]
            errorMessage = nil
            acceptsRetention = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            EditorialKicker(text: "YouCam photo try-on")
            Text("Build the look, piece by piece.")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1)
            Text("Choose a photo of yourself, then select clothes and accessories. Selected items are applied in order to one finished image.")
                .foregroundStyle(.secondary)
        }
    }

    private var personStage: some View {
        let hasPersonPhoto = personImages[photoContext] != nil
        return VStack(spacing: 0) {
            if let display = resultImages[photoContext] ?? personImages[photoContext] {
                DataImage(data: display, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                    .clipped()
                    .background(Color(uiColor: .secondarySystemBackground))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: photoContext.cameraSymbol)
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(StylezamDesign.cobalt)
                    Text(photoContext.emptyPhotoTitle)
                        .font(.title3.weight(.semibold))
                    Text(photoContext.guidance)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 245)
            }

            EditorialRule()

            HStack(spacing: 10) {
                Button {
                    isCameraPresented = true
                } label: {
                    Label(hasPersonPhoto ? "Retake" : "Take photo", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .stylezamGlassButton(prominent: true)
                .tint(StylezamDesign.cobalt)

                PhotosPicker(selection: $personPickerItem, matching: .images) {
                    Label(hasPersonPhoto ? "Replace" : "Photos", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .stylezamGlassButton()
            }
            .padding(12)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(StylezamDesign.hairline) }
    }

    private var itemTray: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                EditorialSectionHeader(title: "Try-on rail", detail: "\(selectedItems.count) selected")
                Spacer()
                Menu {
                    Picker("Category", selection: $newCategory) {
                        ForEach(photoContext.categories, id: \.self) { Text($0.title).tag($0) }
                    }
                    PhotosPicker(selection: $productPickerItem, matching: .images) {
                        Label("Add product photo", systemImage: "photo.badge.plus")
                    }
                    Button { isLibraryPresented = true } label: {
                        Label("Add from Library", systemImage: "square.stack.3d.up")
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 36, height: 36)
                }
                .stylezamGlassButton()
            }

            if isLoadingFoundProducts {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(foundProductStatus ?? "Preparing the found piece")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            } else if let foundProductStatus, !tray.isEmpty {
                Label(foundProductStatus, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !isLoadingFoundProducts && !tray.contains(where: { photoContext.categories.contains($0.category) }) {
                Text(tray.isEmpty
                     ? "Use + to add a product image or an existing Library piece."
                     : "No \(photoContext.title.lowercased()) pieces yet. Use + to add one, or switch photo type.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach($tray) { $item in
                            if photoContext.categories.contains(item.category) { trayCard($item) }
                        }
                    }
                }
            }
        }
    }

    private func trayCard(_ item: Binding<TryOnTrayItem>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Button {
                    item.wrappedValue.isSelected.toggle()
                } label: {
                    DataImage(data: item.wrappedValue.imageData)
                        .frame(width: 112, height: 132).clipped()
                        .opacity(item.wrappedValue.isSelected ? 1 : 0.38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.wrappedValue.isSelected ? "Deselect \(item.wrappedValue.title)" : "Select \(item.wrappedValue.title)")
                Button {
                    let removedContext = context(for: item.wrappedValue.category)
                    tray.removeAll { $0.id == item.wrappedValue.id }
                    invalidateResult(for: removedContext)
                } label: {
                    Image(systemName: "xmark").font(.caption.bold()).frame(width: 44, height: 44)
                }
                .stylezamGlassButton()
                .padding(5)
            }
            Toggle(isOn: item.isSelected) {
                Text(item.wrappedValue.title).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .toggleStyle(.switch).controlSize(.mini)
            Menu {
                ForEach(TryOnCategory.allCases, id: \.self) { category in
                    Button {
                        let previousContext = context(for: item.wrappedValue.category)
                        invalidateResult(for: previousContext)
                        item.wrappedValue.category = category
                        photoContext = context(for: category)
                    } label: {
                        Label(category.title, systemImage: item.wrappedValue.category == category ? "checkmark" : category.symbol)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(item.wrappedValue.category.title)
                    Image(systemName: "chevron.down")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Button {
                guard item.wrappedValue.sourceWardrobeID == nil else { return }
                do {
                    let saved = try model.library.addWardrobeItem(
                        title: item.wrappedValue.title,
                        category: item.wrappedValue.category,
                        imageData: item.wrappedValue.imageData,
                        sourceProduct: item.wrappedValue.sourceProduct
                    )
                    item.wrappedValue.sourceWardrobeID = saved.id
                } catch { errorMessage = error.localizedDescription }
            } label: {
                Label(item.wrappedValue.sourceWardrobeID == nil ? "Save" : "Saved", systemImage: item.wrappedValue.sourceWardrobeID == nil ? "bookmark" : "bookmark.fill")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.wrappedValue.sourceWardrobeID == nil ? StylezamDesign.cobalt : .secondary)
        }
        .frame(width: 112)
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
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Toggle("Allow this try-on upload", isOn: $acceptsRetention)
                .font(.subheadline)
                .disabled(personImages[photoContext] == nil || selectedItems.isEmpty)

            Button {
                startRender()
            } label: {
                HStack {
                    Text(isRendering ? status : "Create try-on")
                    Spacer()
                    if isRendering { ProgressView().tint(.white) }
                    else { Image(systemName: "sparkles") }
                }
                .fontWeight(.semibold).padding(.horizontal, 18)
                .frame(maxWidth: .infinity).frame(height: 54)
            }
            .stylezamGlassButton(prominent: true)
            .tint(StylezamDesign.cobalt)
            .disabled(!isReadyToRender || isRendering)

            if let resultImage = resultImages[photoContext], let jobID = resultJobIDs[photoContext] {
                Button {
                    do {
                        _ = try model.library.addTryOn(
                            jobID: jobID,
                            title: selectedItems.map(\.title).joined(separator: " + "),
                            imageData: resultImage
                        )
                        status = "Saved to Library"
                        savedJobIDs.insert(jobID)
                    } catch { errorMessage = error.localizedDescription }
                } label: { Label(savedJobIDs.contains(jobID) ? "Saved to Library" : "Save look to Library", systemImage: savedJobIDs.contains(jobID) ? "bookmark.fill" : "bookmark") }
                .stylezamGlassButton()
                .disabled(savedJobIDs.contains(jobID))
            }
            Text("YouCam documents that uploaded and generated files may be retained for up to 30 days; result links expire sooner. Generative passes may alter earlier details. Previews show appearance, not physical size or fit.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var credentialPanel: some View {
        if hasCredential {
            HStack(spacing: 10) {
                if isCheckingConnection {
                    ProgressView()
                } else {
                    Image(systemName: isConnectionVerified ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
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
                if !isCheckingConnection && !isConnectionVerified {
                    Button("Retry") { Task { await checkConnection() } }
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                EditorialSectionHeader(title: "Connect YouCam", detail: "Prototype credential")
                SecureField("YouCam API key", text: $credential)
                    .textContentType(.password)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                Button("Save securely on this device") {
                    do {
                        try YouCamCredentialStore.save(credential)
                        credential = ""
                        hasCredential = true
                        Task { await checkConnection() }
                    } catch { errorMessage = error.localizedDescription }
                }
                .stylezamGlassButton()
                .disabled(credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("For production, the app should call a Stylezam server that holds this credential. A mobile app bundle cannot keep a shared bearer token secret.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func startRender() {
        guard let personImage = personImages[photoContext] else { return }
        let selected = selectedItems
        errorMessage = nil
        invalidateResult(for: photoContext)
        isRendering = true
        let renderingContext = photoContext
        let renderID = UUID()
        activeRenderID = renderID
        activeRenderContext = renderingContext
        renderTask = Task {
            do {
                let output = try await service.render(personImage: personImage, items: selected, gender: gender) { current, total, label in
                    await MainActor.run { status = current == total ? label : "\(label) · \(current + 1)/\(total)" }
                }
                guard activeRenderID == renderID, !Task.isCancelled else { return }
                resultImages[renderingContext] = output.imageData
                resultJobIDs[renderingContext] = output.jobID
            } catch is CancellationError {
            } catch {
                if activeRenderID == renderID { errorMessage = error.localizedDescription }
            }
            if activeRenderID == renderID {
                isRendering = false
                activeRenderID = nil
                activeRenderContext = nil
                renderTask = nil
            }
        }
    }

    private var selectedItems: [TryOnTrayItem] {
        tray.filter { $0.isSelected && photoContext.categories.contains($0.category) }
    }

    private var isReadyToRender: Bool {
        personImages[photoContext] != nil
            && !selectedItems.isEmpty
            && acceptsRetention
            && hasCredential
            && isConnectionVerified
            && !isLoadingFoundProducts
    }

    private var readinessMessage: String {
        if isLoadingFoundProducts { return foundProductStatus ?? "Preparing the found piece" }
        if personImages[photoContext] == nil { return "Take or choose your \(photoContext.photoNoun) photo" }
        if selectedItems.isEmpty { return "Add or select one \(photoContext.title.lowercased()) piece" }
        if !hasCredential { return "Connect the YouCam API key below" }
        if isCheckingConnection { return "Checking the YouCam connection" }
        if !isConnectionVerified { return "Retry the YouCam connection" }
        if !acceptsRetention { return "Allow this upload to continue" }
        return "Ready to create a real YouCam preview"
    }

    private var readinessSymbol: String {
        if isReadyToRender { return "checkmark.circle.fill" }
        if isLoadingFoundProducts || isCheckingConnection { return "clock" }
        return "circle.dashed"
    }

    private var selectionSignature: String {
        tray.map { "\($0.id.uuidString):\($0.category.rawValue):\($0.isSelected)" }.joined(separator: "|")
    }

    private func invalidateResult(for context: TryOnPhotoContext) {
        if activeRenderContext == context { cancelActiveRender() }
        resultImages[context] = nil
        resultJobIDs[context] = nil
    }

    private func cancelActiveRender() {
        renderTask?.cancel()
        renderTask = nil
        activeRenderID = nil
        activeRenderContext = nil
        isRendering = false
    }

    private func context(for category: TryOnCategory) -> TryOnPhotoContext {
        TryOnPhotoContext.allCases.first { $0.categories.contains(category) } ?? .outfit
    }

    private func normalizedData(from item: PhotosPickerItem) async -> Data? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await ImageEncoding.normalizedJPEGAsync(from: data)
    }

    private func setPersonPhoto(_ data: Data, for context: TryOnPhotoContext) {
        personImages[context] = data
        invalidateResult(for: context)
        acceptsRetention = false
        errorMessage = nil
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

    @MainActor
    private func addPendingProduct(_ product: ProductResultDTO) async {
        guard let url = product.imageURL else {
            errorMessage = "This result has no product image for YouCam. Choose another result or add a product photo from the try-on rail."
            return
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue("image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw YouCamTryOnError.server("The store would not provide this product image. Choose another result or add a clearer product photo.")
            }
            guard data.count < 25_000_000,
                  let normalized = await ImageEncoding.normalizedJPEGAsync(from: data)
            else {
                throw YouCamTryOnError.server("The found product image could not be prepared for YouCam.")
            }
            let category = TryOnCategory.infer(category: product.category, title: product.title)
            appendTrayItem(TryOnTrayItem(title: product.title, category: category, imageData: normalized, sourceProduct: product))
            foundProductStatus = "\(category.title) ready"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendTrayItem(_ item: TryOnTrayItem) {
        let isDuplicate = tray.contains { existing in
            if let wardrobeID = item.sourceWardrobeID, existing.sourceWardrobeID == wardrobeID { return true }
            if let productID = item.sourceProduct?.id, existing.sourceProduct?.id == productID { return true }
            return false
        }
        guard !isDuplicate else {
            photoContext = context(for: item.category)
            return
        }
        tray.append(item)
        let itemContext = context(for: item.category)
        invalidateResult(for: itemContext)
        photoContext = itemContext
    }

}

private struct TryOnCameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let context: TryOnPhotoContext
    let onCapture: (Data) -> Void

    @State private var camera = CameraSessionController(position: .front)
    @State private var captureTask: Task<Void, Never>?
    @State private var didCapture = false
    @State private var countdownValue: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isReady {
                CameraPreview(
                    session: camera.driver.session,
                    rotationChanged: camera.driver.setVideoRotationAngle
                )
                .ignoresSafeArea()
            } else if let error = camera.errorMessage {
                cameraUnavailable(error)
            } else {
                ProgressView("Opening camera")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            cameraChrome

            if let countdownValue {
                countdownOverlay(countdownValue)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .statusBarHidden()
        .task { await camera.start() }
        .onDisappear {
            captureTask?.cancel()
            camera.stop()
        }
        .sensoryFeedback(.success, trigger: didCapture)
    }

    private var cameraChrome: some View {
        VStack(spacing: 0) {
            HStack {
                toolButton(icon: "xmark", label: "Close camera") {
                    captureTask?.cancel()
                    dismiss()
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("TRY-ON PHOTO")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                    Text(context.title)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                Spacer()
                toolButton(
                    icon: camera.flashEnabled ? "bolt.fill" : "bolt.slash",
                    label: camera.flashEnabled ? "Turn flash off" : "Turn flash on"
                ) {
                    camera.flashEnabled.toggle()
                }
                .disabled(captureTask != nil)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 20) {
                VStack(spacing: 5) {
                    Text(context.captureTitle)
                        .font(.headline)
                    Text(context.captureGuidance)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 330)
                }
                .foregroundStyle(.white)

                HStack {
                    toolButton(
                        icon: "arrow.triangle.2.circlepath.camera",
                        label: "Switch camera"
                    ) {
                        Task { await camera.switchCamera() }
                    }
                    .disabled(captureTask != nil)

                    Spacer()

                    Button {
                        startCountdown()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 78, height: 78)
                            Circle()
                                .fill(.white)
                                .frame(width: 64, height: 64)
                                .scaleEffect(camera.isCapturingPhoto ? 0.86 : 1)
                        }
                    }
                    .buttonStyle(TryOnShutterButtonStyle())
                    .disabled(!camera.isReady || camera.isCapturingPhoto || captureTask != nil)
                    .accessibilityLabel("Take try-on photo")

                    Spacer()

                    VStack(spacing: 2) {
                        Image(systemName: "timer")
                        Text("3s")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 48, height: 48)
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 24)
        }
    }

    private func startCountdown() {
        guard captureTask == nil else { return }
        captureTask = Task {
            defer {
                countdownValue = nil
                captureTask = nil
            }

            for value in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                withAnimation(StylezamMotion.quickSpring) {
                    countdownValue = value
                }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }

            withAnimation(.easeOut(duration: 0.16)) {
                countdownValue = nil
            }
            guard let data = await camera.capturePhoto(), !Task.isCancelled else { return }
            didCapture = true
            onCapture(data)
            try? await Task.sleep(for: .milliseconds(120))
            dismiss()
        }
    }

    private func countdownOverlay(_ value: Int) -> some View {
        VStack(spacing: 7) {
            Text("\(value)")
                .font(.system(size: 82, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            Text("Step back and hold your position")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photo in \(value) seconds")
    }

    private func toolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.16), lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func cameraUnavailable(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34))
            Text("Camera unavailable")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .stylezamGlassButton(prominent: true)
                .tint(.white)
                .foregroundStyle(.black)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 34)
    }
}

private struct TryOnShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension TryOnPhotoContext {
    var photoNoun: String {
        switch self {
        case .outfit: "outfit"
        case .handAndWrist: "hand or wrist"
        case .faceAndNeck: "face and neck"
        }
    }

    var emptyPhotoTitle: String {
        switch self {
        case .outfit: "Take a photo of yourself"
        case .handAndWrist: "Take a hand or wrist photo"
        case .faceAndNeck: "Take a face and neck photo"
        }
    }

    var cameraSymbol: String {
        switch self {
        case .outfit: "person.crop.rectangle.badge.plus"
        case .handAndWrist: "hand.raised"
        case .faceAndNeck: "person.crop.square"
        }
    }

    var captureTitle: String {
        switch self {
        case .outfit: "Keep one person in frame"
        case .handAndWrist: "Show the full hand or wrist"
        case .faceAndNeck: "Face forward with ears visible"
        }
    }

    var captureGuidance: String {
        switch self {
        case .outfit: "Stand facing forward. Keep the body area needed for the selected clothing fully visible."
        case .handAndWrist: "Use a clear close-up with no sleeve, hair, or object covering the target area."
        case .faceAndNeck: "Use even light and keep your face, ears, shoulders, and neckline unobstructed."
        }
    }
}

private struct TryOnLibraryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onSelect: (TryOnTrayItem) -> Void
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if !model.library.wardrobeItems.isEmpty {
                    Section("Saved for try-on") {
                        ForEach(model.library.wardrobeItems) { item in
                            Button {
                                Task { await addWardrobeItem(item) }
                            } label: {
                                HStack { LocalFileImage(url: model.library.imageURL(for: item), contentMode: .fit).frame(width: 54, height: 64); Text(item.title) }
                            }
                        }
                    }
                }
                if !model.library.products.isEmpty {
                    Section("Saved products") {
                        ForEach(model.library.products) { saved in
                            Button {
                                Task { await addProduct(saved.product) }
                            } label: {
                                HStack {
                                    ProductImage(url: saved.product.imageURL).frame(width: 54, height: 64)
                                    VStack(alignment: .leading) { Text(saved.product.title); Text(saved.product.merchant).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                ForEach(model.library.scans) { scan in
                    Section(scan.createdAt.formatted(date: .abbreviated, time: .omitted)) {
                        ForEach(scan.items.filter { scan.labelState != .enriched || $0.accepted }) { garment in
                            if let url = model.library.cropURL(for: garment) {
                                Button {
                                    Task { await addGarment(garment, url: url) }
                                } label: {
                                    HStack { LocalFileImage(url: url, contentMode: .fit).frame(width: 54, height: 64); Text(garment.title) }
                                }
                            }
                        }
                    }
                }
                if model.library.scans.isEmpty && model.library.products.isEmpty && model.library.wardrobeItems.isEmpty {
                    ContentUnavailableView("No pieces yet", systemImage: "tshirt", description: Text("Detect a look first, or add a product photo from the try-on rail."))
                }
                if let message { Text(message).font(.caption).foregroundStyle(.red) }
            }
            .navigationTitle("Add from Library")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    @MainActor
    private func addWardrobeItem(_ item: SavedWardrobeItem) async {
        let url = model.library.imageURL(for: item)
        guard let data = try? await Task.detached(priority: .userInitiated, operation: { try Data(contentsOf: url) }).value else {
            message = "That saved item could not be read."; return
        }
        onSelect(TryOnTrayItem(title: item.title, category: item.category, imageData: data, sourceProduct: item.sourceProduct, sourceWardrobeID: item.id))
        dismiss()
    }

    @MainActor
    private func addGarment(_ garment: SavedGarment, url: URL) async {
        guard let data = try? await Task.detached(priority: .userInitiated, operation: { try Data(contentsOf: url) }).value else {
            message = "That detected piece could not be read."; return
        }
        onSelect(TryOnTrayItem(title: garment.title, category: category(for: garment.localLabel), imageData: data))
        dismiss()
    }

    @MainActor
    private func addProduct(_ product: ProductResultDTO) async {
        guard let url = product.imageURL else { message = "This product has no usable image."; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard data.count < 10_000_000,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let normalized = await ImageEncoding.normalizedJPEGAsync(from: data)
            else { message = "The product image could not be downloaded."; return }
            let category = TryOnCategory.infer(category: product.category, title: product.title)
            onSelect(TryOnTrayItem(title: product.title, category: category, imageData: normalized, sourceProduct: product))
            dismiss()
        } catch { message = error.localizedDescription }
    }

    private func category(for label: String) -> TryOnCategory { TryOnCategory.infer(from: label) }
}
