import SwiftUI

struct TryOnCameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let context: TryOnPhotoContext
    let onCapture: (Data) -> Void

    @State private var camera = CameraSessionController(position: .front)
    @State private var captureTask: Task<Void, Never>?
    @State private var didCapture = false
    @State private var countdownValue: Int?
    @State private var zoomGestureAnchor: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isReady {
                CameraPreview(
                    session: camera.driver.session,
                    rotationChanged: camera.driver.setVideoRotationAngle
                )
                .ignoresSafeArea()
                .simultaneousGesture(cameraZoomGesture)
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

            VStack(spacing: 16) {
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

                zoomControls

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

    private var zoomControls: some View {
        HStack(spacing: 4) {
            ForEach(camera.availableZoomPresets, id: \.self) { factor in
                Button {
                    camera.setZoomFactor(factor)
                } label: {
                    Text(zoomLabel(factor))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(
                            abs(camera.zoomFactor - factor) < 0.08 ? .black : .white
                        )
                        .frame(minWidth: 34, minHeight: 30)
                        .background(
                            abs(camera.zoomFactor - factor) < 0.08
                                ? Color.white
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom \(zoomLabel(factor))")
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5) }
        .opacity(camera.maximumZoomFactor > camera.minimumZoomFactor + 0.01 ? 1 : 0)
        .accessibilityHidden(camera.maximumZoomFactor <= camera.minimumZoomFactor + 0.01)
    }

    private var cameraZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                let anchor = zoomGestureAnchor ?? camera.zoomFactor
                if zoomGestureAnchor == nil { zoomGestureAnchor = anchor }
                camera.setZoomFactor(anchor * magnification)
            }
            .onEnded { _ in
                zoomGestureAnchor = nil
            }
    }

    private func zoomLabel(_ factor: CGFloat) -> String {
        factor.rounded() == factor
            ? "\(Int(factor))×"
            : String(format: "%.1f×", factor)
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
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photo in \(value) seconds")
    }

    private func toolButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
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
    var captureTitle: String {
        switch self {
        case .outfit: "Keep one person in frame"
        case .handAndWrist: "Show the full hand or wrist"
        case .faceAndNeck: "Face forward with ears visible"
        }
    }

    var captureGuidance: String {
        switch self {
        case .outfit:
            "Stand facing forward. Keep the body area needed for the selected clothing fully visible."
        case .handAndWrist:
            "Use a clear close-up with no sleeve, hair, or object covering the target area."
        case .faceAndNeck:
            "Use even light and keep your face, ears, shoulders, and neckline unobstructed."
        }
    }
}
