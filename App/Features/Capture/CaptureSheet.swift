import PhotosUI
import SwiftUI
import UIKit

struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var imageData: Data?
    @State private var origin: CaptureOrigin = .photoLibrary
    @State private var photoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var importMessage: String?
    @State private var isSubmitting = false
    @State private var feedbackEvent = 0

    private var canSearch: Bool {
        !isSubmitting && (
            imageData != nil
                || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageTitle(
                        title: "Search anything you see.",
                        subtitle: "Choose a photo, take one now, or describe the item. Add both when you want a more specific result."
                    )
                    .padding(.top, 10)
                    .motionReveal()

                    captureCanvas
                        .motionReveal(delay: 0.05, distance: 22)
                    sourceButtons
                        .motionReveal(delay: 0.1)
                    queryField
                        .motionReveal(delay: 0.15)

                    if let message = importMessage ?? model.lastError {
                        Label(message, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 10) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: imageData == nil ? "text.magnifyingglass" : "sparkle.magnifyingglass")
                            }
                            Text(isSubmitting ? "Starting search…" : primaryTitle)
                                .fontWeight(.semibold)
                            Spacer()
                            if !isSubmitting {
                                Image(systemName: "arrow.right")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .padding(.horizontal, 18)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(StylezamDesign.cobalt)
                    .disabled(!canSearch)
                    .padding(.bottom, 28)
                    .animation(StylezamMotion.quickSpring, value: canSearch)
                    .motionReveal(delay: 0.2)
                }
                .padding(.horizontal, StylezamDesign.pageInset)
            }
            .background(StylezamDesign.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 9) {
                        BrandMarkView(size: 34)
                        Text("New search")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Close")
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
                imageData = data
                origin = .camera
                importMessage = nil
                feedbackEvent += 1
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let loaded = try? await newValue.loadTransferable(type: Data.self),
                   let normalized = ImageEncoding.normalizedJPEG(from: loaded)
                {
                    imageData = normalized
                    origin = .photoLibrary
                    importMessage = nil
                    feedbackEvent += 1
                } else {
                    importMessage = "That photo format could not be read."
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: feedbackEvent)
    }

    private var primaryTitle: String {
        if imageData != nil { return "Find this look" }
        return "Search these words"
    }

    private var captureCanvas: some View {
        ZStack(alignment: .topTrailing) {
            if let imageData {
                DataImage(data: imageData)
                    .frame(maxWidth: .infinity)
                    .frame(height: 350)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack {
                    Text(origin.captureLabel)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(17)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                emptyCanvas
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }

            if imageData != nil {
                Button {
                    imageData = nil
                    photoItem = nil
                    importMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.glass)
                .padding(12)
                .accessibilityLabel("Remove image")
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.5)
        }
        .animation(StylezamMotion.softSpring, value: imageData != nil)
    }

    private var emptyCanvas: some View {
        ZStack {
            LivingCobaltBackdrop()

            VStack(spacing: 14) {
                OrbitingBrandMark(size: 136)
                VStack(spacing: 5) {
                    Text("Add a fashion photo")
                        .font(.title3.weight(.semibold))
                    Text("A full outfit is fine—you can choose a detected item after the first search.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 285)
                }
                .foregroundStyle(.white)
            }
            .padding(24)
        }
        .frame(height: 330)
    }

    private var sourceButtons: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                sourceButton(title: "Camera", icon: "camera") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isCameraPresented = true
                    } else {
                        importMessage = "Camera is not available on this device."
                    }
                }
                sourceButton(title: "Photos", icon: "photo.on.rectangle") {
                    isPhotoPickerPresented = true
                }
                sourceButton(title: "Paste", icon: "doc.on.clipboard") {
                    pasteFromClipboard()
                }
            }
        }
    }

    private func sourceButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
        }
        .buttonStyle(.glass)
    }

    private var queryField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(imageData == nil ? "Describe the item" : "Add a detail")
                    .font(.headline)
                Spacer()
                Text(imageData == nil ? "Required" : "Optional")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            TextField(
                "For example: navy cropped jacket under $200",
                text: $query,
                axis: .vertical
            )
            .lineLimit(2...4)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: StylezamDesign.compactRadius, style: .continuous)
            )
        }
    }

    private func submit() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = SearchInput(
            query: trimmedQuery.isEmpty ? nil : trimmedQuery,
            imageData: imageData,
            origin: imageData == nil ? .text : origin
        )
        guard !input.isEmpty else { return }
        isSubmitting = true
        Task {
            let id = await model.startSearch(input)
            if id == nil {
                isSubmitting = false
            }
        }
    }

    private func pasteFromClipboard() {
        if let image = UIPasteboard.general.image,
           let data = ImageEncoding.normalizedJPEG(from: image)
        {
            imageData = data
            origin = .clipboard
            importMessage = "Image pasted."
            feedbackEvent += 1
        } else if let text = UIPasteboard.general.string, !text.isEmpty {
            query = text
            origin = .clipboard
            importMessage = "Text pasted."
            feedbackEvent += 1
        } else {
            importMessage = "The clipboard does not contain an image or text."
        }
    }
}

private extension CaptureOrigin {
    var captureLabel: String {
        switch self {
        case .camera: "Camera photo"
        case .photoLibrary: "Photo library"
        case .text: "Text search"
        case .clipboard: "Clipboard"
        case .shareExtension: "Shared image"
        case .screenCapture: "Screen capture"
        }
    }
}
