import PhotosUI
import SwiftUI
import UIKit

struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let initialMode: CaptureLaunchMode

    @State private var imageData: Data?
    @State private var origin: CaptureOrigin = .photoLibrary
    @State private var photoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var importMessage: String?
    @State private var isSubmitting = false
    @State private var feedbackEvent = 0
    @State private var didApplyInitialMode = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageTitle(
                        title: "Add a photo",
                        subtitle: "Use the whole outfit or a close crop. You can choose a detected item after the first pass."
                    )
                    .padding(.top, 10)

                    captureCanvas
                    sourceButtons

                    if let message = importMessage ?? model.lastError {
                        Label(message, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                }
                .padding(.horizontal, StylezamDesign.pageInset)
                .padding(.bottom, 104)
            }
            .background(StylezamDesign.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    submit()
                } label: {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(isSubmitting ? "Starting…" : "Find products")
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
                .disabled(imageData == nil || isSubmitting)
                .padding(.horizontal, StylezamDesign.pageInset)
                .padding(.vertical, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
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
                   let normalized = await ImageEncoding.normalizedJPEGAsync(from: loaded)
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
        .task {
            guard !didApplyInitialMode else { return }
            didApplyInitialMode = true
            await Task.yield()
            switch initialMode {
            case .chooser:
                break
            case .camera:
                openCamera()
            case .photos:
                isPhotoPickerPresented = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: feedbackEvent)
    }

    private var captureCanvas: some View {
        ZStack(alignment: .topTrailing) {
            if let imageData {
                DataImage(data: imageData)
                    .frame(maxWidth: .infinity)
                    .frame(height: 390)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.48)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Label(origin.captureLabel, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(17)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    CaptureFrameCorners()
                        .stroke(.primary.opacity(0.6), lineWidth: 1.5)
                        .padding(22)
                    VStack(spacing: 15) {
                        Image(systemName: "photo")
                            .font(.system(size: 42, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text("Add a fashion photo")
                            .font(.title3.weight(.semibold))
                        Text("Camera, Photos, or clipboard")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                }
                .frame(height: 350)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.5)
        }
        .animation(StylezamMotion.softSpring, value: imageData != nil)
    }

    private var sourceButtons: some View {
        HStack(spacing: 10) {
            sourceButton(title: "Camera", icon: "camera") { openCamera() }
            sourceButton(title: "Photos", icon: "photo.on.rectangle") {
                isPhotoPickerPresented = true
            }
            sourceButton(title: "Paste", icon: "doc.on.clipboard") {
                pasteImage()
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
            .frame(height: 68)
        }
        .buttonStyle(.bordered)
    }

    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            isCameraPresented = true
        } else {
            importMessage = "Camera is not available on this device. Choose a photo instead."
        }
    }

    private func submit() {
        guard let imageData else { return }
        isSubmitting = true
        Task {
            let id = await model.startSearch(
                SearchInput(query: nil, imageData: imageData, origin: origin)
            )
            if id == nil {
                isSubmitting = false
            }
        }
    }

    private func pasteImage() {
        guard let image = UIPasteboard.general.image,
              let data = ImageEncoding.normalizedJPEG(from: image)
        else {
            importMessage = "The clipboard does not contain an image."
            return
        }
        imageData = data
        origin = .clipboard
        importMessage = "Image pasted."
        feedbackEvent += 1
    }
}

private struct CaptureFrameCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.11
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

private extension CaptureOrigin {
    var captureLabel: String {
        switch self {
        case .camera: "Camera photo"
        case .photoLibrary: "Photo library"
        case .text: "Text search"
        case .clipboard: "Clipboard image"
        case .shareExtension: "Shared image"
        case .screenCapture: "Screen capture"
        }
    }
}
