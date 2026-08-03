import Photos
import PhotosUI
import SwiftUI
import UIKit

struct TryOnView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let product: ProductResultDTO
    let productImageURL: URL

    @State private var viewModel: TryOnViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var saveMessage: String?

    init(
        product: ProductResultDTO,
        productImageURL: URL,
        settings: SettingsStore
    ) {
        self.product = product
        self.productImageURL = productImageURL
        _viewModel = State(
            initialValue: TryOnViewModel(
                settings: settings,
                productImageURL: productImageURL
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()
                imageStage
                    .ignoresSafeArea()
                    .animation(StylezamMotion.softSpring, value: viewModel.isShowingResult)
                stageLabel
                bottomPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .motionReveal(delay: 0.08, distance: 22)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .buttonStyle(.glass)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("STYLEZAM")
                            .font(.caption2.weight(.black))
                            .tracking(1.2)
                        Text("APPEARANCE PREVIEW")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1)
                    }
                    .foregroundStyle(.white)
                }
                if let resultFileURL = viewModel.resultFileURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: resultFileURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $photoItem,
            matching: .images
        )
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { data in
                Task { await viewModel.replacePersonImage(with: data) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let normalized = ImageEncoding.normalizedJPEG(from: data)
                {
                    await viewModel.replacePersonImage(with: normalized)
                    saveMessage = nil
                } else {
                    viewModel.errorMessage = "That photo could not be read."
                }
            }
        }
        .onDisappear {
            Task { await viewModel.deleteRemoteJobIfNeeded() }
        }
        .sensoryFeedback(.selection, trigger: viewModel.isShowingResult)
    }

    @ViewBuilder
    private var imageStage: some View {
        if viewModel.isShowingResult,
           let resultImageData = viewModel.resultImageData
        {
            DataImage(data: resultImageData)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .transition(.scale(scale: 1.025).combined(with: .opacity))
        } else if let data = viewModel.personImageData {
            DataImage(data: data)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .transition(.opacity)
        } else {
            emptyStage
                .transition(.opacity)
        }
    }

    private var emptyStage: some View {
        ZStack {
            Color.black
            LivingCobaltBackdrop(intensity: 0.72)
                .opacity(0.78)
            VStack(spacing: 18) {
                OrbitingBrandMark(size: 148)
                Text("See the piece on you")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .tracking(-0.7)
                Text("Choose a clear, front-facing photo. Nothing is uploaded until you ask Stylezam to generate the preview.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 24)
            .padding(.bottom, 150)
        }
    }

    private var stageLabel: some View {
        Group {
            if viewModel.personImageData != nil {
                EditorialKicker(
                    text: viewModel.isShowingResult && viewModel.resultImageData != nil
                        ? "Generated appearance preview"
                        : "Original person photo",
                    color: .white.opacity(0.78)
                )
                .padding(.horizontal, 12)
                .frame(height: 32)
                .glassEffect(.regular, in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 64)
        .padding(.horizontal, 14)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            if viewModel.resultImageData != nil {
                Picker("View", selection: $viewModel.isShowingResult) {
                    Text("Original").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
            }

            HStack(alignment: .top, spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    EditorialKicker(text: product.brand ?? product.merchant)
                    Text(product.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    Text([product.price?.formatted, product.merchant].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ProductImage(url: product.imageURL)
                    .frame(width: 58, height: 70)
                    .padding(4)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let job = viewModel.job, !job.status.isTerminal {
                processingPanel(title: job.phase.title, progress: job.progress)
            } else if viewModel.job?.status == .completed,
                      viewModel.resultImageData == nil,
                      viewModel.errorMessage == nil
            {
                processingPanel(title: "Securing the preview locally", progress: 0.96)
            }

            if let completionMessage = viewModel.completionMessage {
                Label(completionMessage, systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            actionButtons

            Text("Appearance visualization only — it does not measure size, drape, comfort, or fit.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(17)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
    }

    private func processingPanel(title: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ProgressView()
            }
            AnimatedProgressCapsule(progress: progress)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if viewModel.personImageData == nil {
            HStack(spacing: 10) {
                Button {
                    isPhotoPickerPresented = true
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(StylezamDesign.cobalt)

                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isCameraPresented = true
                    } else {
                        viewModel.errorMessage = "Camera is not available on this device."
                    }
                } label: {
                    Label("Camera", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        } else if viewModel.resultImageData != nil {
            HStack(spacing: 10) {
                Button {
                    Task { await savePreviewToPhotos() }
                } label: {
                    Label("Save preview", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(StylezamDesign.cobalt)

                Button {
                    model.library.toggleSaved(product)
                } label: {
                    Image(systemName: model.library.isSaved(product) ? "bookmark.fill" : "bookmark")
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(model.library.isSaved(product) ? "Remove product bookmark" : "Bookmark product")
            }

            Button("Use another person photo") {
                isPhotoPickerPresented = true
            }
            .font(.caption.weight(.semibold))
        } else if !viewModel.isProcessing {
            CobaltActionButton(title: "Generate preview", systemImage: "figure.stand") {
                Task { await viewModel.submit() }
            }
            Button("Choose another photo") {
                isPhotoPickerPresented = true
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func savePreviewToPhotos() async {
        guard let data = viewModel.resultImageData else { return }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            saveMessage = "Photo access was not granted. Use Share to export the local file instead."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            saveMessage = "Preview saved to Photos."
        } catch {
            saveMessage = "The preview could not be saved: \(error.localizedDescription)"
        }
    }
}
