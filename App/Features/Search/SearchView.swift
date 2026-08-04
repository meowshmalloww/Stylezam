import PhotosUI
import SwiftUI
import UIKit

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var referenceImageData: Data?
    @State private var referenceItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction
                referenceStage
                sourceControls
                scanAction
                futureSearchNote
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(StylezamDesign.canvas)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { data in
                referenceImageData = data
                message = nil
            }
            .ignoresSafeArea()
        }
        .onChange(of: referenceItem) { _, item in
            guard let item else { return }
            Task { await loadReference(item) }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            EditorialKicker(text: "On-device image scan")
            Text("Start with a fashion image.")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1)
            Text("Stylezam will detect the visible pieces, cut out each one, and save the result in Library—all on this iPhone.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var referenceStage: some View {
        Group {
            if let referenceImageData {
                ZStack(alignment: .topTrailing) {
                    DataImage(data: referenceImageData)
                        .frame(maxWidth: .infinity)
                        .frame(height: 310)
                        .clipped()

                    Button {
                        self.referenceImageData = nil
                        referenceItem = nil
                        message = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.glass)
                    .padding(12)
                    .accessibilityLabel("Remove image")
                }
            } else {
                PhotosPicker(selection: $referenceItem, matching: .images) {
                    VStack(spacing: 14) {
                        ReferenceImageAddGlyph()
                            .frame(width: 48, height: 48)
                        VStack(spacing: 4) {
                            Text("Add a fashion image")
                                .font(.headline)
                            Text("Choose a photo, take one, or paste from Clipboard")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 238)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 1)
        }
    }

    private var sourceControls: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $referenceItem, matching: .images) {
                SearchSourceLabel(title: "Photos", icon: "photo.on.rectangle")
            }
            .buttonStyle(.glass)

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isCameraPresented = true
                } else {
                    message = "Camera is not available on this device."
                }
            } label: {
                SearchSourceLabel(title: "Camera", icon: "camera")
            }
            .buttonStyle(.glass)

            Button {
                pasteReferenceImage()
            } label: {
                SearchSourceLabel(title: "Paste", icon: "doc.on.clipboard")
            }
            .buttonStyle(.glass)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SearchSourceLabel: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
            Text(title)
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
    }
}

private extension SearchView {

    private var scanAction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                guard let referenceImageData else { return }
                Task {
                    let scan = await model.processCapture(
                        imageData: referenceImageData,
                        origin: .photoLibrary,
                        mode: .imported
                    )
                    if scan != nil {
                        self.referenceImageData = nil
                        referenceItem = nil
                        message = nil
                    }
                }
            } label: {
                HStack {
                    Text(model.isAnalyzingCapture ? "Detecting on this iPhone" : "Detect pieces")
                    Spacer()
                    if model.isAnalyzingCapture {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                    }
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.glassProminent)
            .tint(StylezamDesign.cobalt)
            .disabled(referenceImageData == nil || model.isAnalyzingCapture)

            if let message = message ?? model.lastError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(model.lastError == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var futureSearchNote: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(StylezamDesign.cobalt)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("Online product search comes next")
                    .font(.headline)
                Text("Text and reference-image matching will appear here after the retrieval quality benchmark. This build does not show placeholder listings or prices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func loadReference(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let normalized = await ImageEncoding.normalizedJPEGAsync(from: data)
        {
            referenceImageData = normalized
            message = nil
        } else {
            message = "That image could not be read. Choose another photo."
        }
    }

    private func pasteReferenceImage() {
        guard let image = UIPasteboard.general.image,
              let data = ImageEncoding.normalizedJPEG(from: image)
        else {
            message = "Clipboard does not contain an image."
            return
        }
        referenceImageData = data
        message = nil
    }
}

private struct ReferenceImageAddGlyph: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "photo")
                .font(.system(size: 33, weight: .regular))
                .foregroundStyle(.primary)
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(StylezamDesign.cobalt, in: Circle())
                .offset(x: 5, y: 5)
        }
    }
}
