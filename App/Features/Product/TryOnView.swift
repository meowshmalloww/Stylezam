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
    @State private var isRendering = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var photoContext: TryOnPhotoContext = .outfit
    @State private var gender: TryOnGender = .female
    @State private var acceptsRetention = false
    @State private var credential = ""
    @State private var hasCredential = YouCamCredentialStore.isConfigured
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
                controls
                credentialPanel
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(StylezamDesign.canvas)
        .navigationTitle("Try On")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: personPickerItem) { _, item in
            guard let item else { return }
            let targetContext = photoContext
            Task {
                personImages[targetContext] = await normalizedData(from: item)
                invalidateResult(for: targetContext)
                acceptsRetention = false
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
            for product in pending where !tray.contains(where: { $0.sourceProduct?.id == product.id }) {
                await addPendingProduct(product)
            }
            let handledIDs = Set(pending.map(\.id))
            model.pendingTryOnProducts.removeAll { product in
                handledIDs.contains(product.id)
            }
        }
        .sheet(isPresented: $isLibraryPresented) {
            TryOnLibraryPicker { item in
                appendTrayItem(item)
            }
                .environment(model)
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
        return ZStack(alignment: .topTrailing) {
            if let display = resultImages[photoContext] ?? personImages[photoContext] {
                DataImage(data: display, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .clipped()
                PhotosPicker(selection: $personPickerItem, matching: .images) {
                    Label("Change photo", systemImage: "photo")
                        .font(.caption.weight(.semibold))
                }
                .stylezamGlassButton()
                .padding(12)
            } else {
                PhotosPicker(selection: $personPickerItem, matching: .images) {
                    VStack(spacing: 14) {
                        Image(systemName: "person.crop.rectangle.badge.plus")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(StylezamDesign.cobalt)
                        Text("Add your photo").font(.headline)
                    }
                    .frame(maxWidth: .infinity).frame(height: 300)
                }
                .buttonStyle(.plain)
            }
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

            if !tray.contains(where: { photoContext.categories.contains($0.category) }) {
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
        VStack(alignment: .leading, spacing: 10) {
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
            .disabled(personImages[photoContext] == nil || selectedItems.isEmpty || isRendering || !acceptsRetention || !hasCredential)

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
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            Toggle("I agree to upload these selected images to YouCam", isOn: $acceptsRetention)
                .font(.caption)
            Text("YouCam documents that uploaded and generated files may be retained for up to 30 days; result links expire sooner. Generative passes may alter earlier details. Previews show appearance, not physical size or fit.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var credentialPanel: some View {
        if !hasCredential {
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

    @MainActor
    private func addPendingProduct(_ product: ProductResultDTO) async {
        guard let url = product.imageURL else { errorMessage = "\(product.title) has no product image."; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard data.count < 10_000_000,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let normalized = await ImageEncoding.normalizedJPEGAsync(from: data)
            else { errorMessage = "\(product.title) could not be added to Try On."; return }
            let category = TryOnCategory.infer(category: product.category, title: product.title)
            appendTrayItem(TryOnTrayItem(title: product.title, category: category, imageData: normalized, sourceProduct: product))
        } catch { errorMessage = error.localizedDescription }
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
