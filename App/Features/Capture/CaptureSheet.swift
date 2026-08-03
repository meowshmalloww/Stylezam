import SwiftUI
import UIKit

/// The center tab is a camera action, not an image-import form.
/// UIImagePickerController provides Apple's real photo camera, shutter,
/// front/rear camera switch, flash controls, retake, and Use Photo flow.
struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isAcceptingCapture = true

    var body: some View {
        Group {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                CameraPicker { imageData in
                    guard isAcceptingCapture else { return }
                    isAcceptingCapture = false
                    Task {
                        await model.startSearch(
                            SearchInput(
                                query: nil,
                                imageData: imageData,
                                origin: .camera
                            )
                        )
                    }
                }
                .ignoresSafeArea()
            } else {
                unavailableCamera
            }
        }
        .background(.black)
        .statusBarHidden()
    }

    private var unavailableCamera: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .tint(.white)
                    .accessibilityLabel("Close camera")

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 38, weight: .regular))
                    Text("Camera unavailable")
                        .font(.title2.weight(.semibold))
                    Text("The camera opens on a physical iPhone. Use Search to add an existing image.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 40)

                Spacer()

                Button {
                    dismiss()
                    model.selectedTab = .search
                } label: {
                    Text("Open Search")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }
}
