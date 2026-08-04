import SwiftUI
import UIKit

struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraSessionController()
    @State private var captureMode: CaptureMode = .photo
    @State private var candidates: [GarmentCandidate] = []
    @State private var guidance: LiveCaptureGuidance = .aimAtFashion
    @State private var frameAspectRatio: CGFloat = 9 / 16
    @State private var isAnalyzingPreview = false
    @State private var previewTask: Task<Void, Never>?
    @State private var stableSignature = ""
    @State private var stableFrameCount = 0
    @State private var bestFrameData: Data?
    @State private var bestFrameScore = 0.0
    @State private var lastAutomaticCapture = Date.distantPast
    @State private var confirmationText: String?
    @State private var captureTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isReady {
                CameraPreview(session: camera.driver.session)
                    .ignoresSafeArea()

                GarmentGuideOverlay(
                    candidates: candidates,
                    sourceAspectRatio: frameAspectRatio
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            } else if let error = camera.errorMessage {
                unavailableCamera(message: error)
            } else {
                ProgressView()
                    .tint(.white)
            }

            cameraChrome

            if camera.isCapturingPhoto || model.isAnalyzingCapture {
                processingNotice
            }
        }
        .statusBarHidden()
        .task {
            camera.onPreviewFrame = { data, aspectRatio in
                handlePreviewFrame(data, aspectRatio: aspectRatio)
            }
            await camera.start()
            updateLiveFrames()
        }
        .onChange(of: captureMode) { _, _ in
            previewTask?.cancel()
            isAnalyzingPreview = false
            candidates = []
            guidance = .aimAtFashion
            stableSignature = ""
            stableFrameCount = 0
            bestFrameData = nil
            bestFrameScore = 0
            updateLiveFrames()
        }
        .onChange(of: model.modelPack.isInstalled) { _, _ in
            updateLiveFrames()
        }
        .onDisappear {
            previewTask?.cancel()
            captureTask?.cancel()
            camera.stop()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: confirmationText)
    }

    private var cameraChrome: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 10)

            Spacer()

            if captureMode == .live, !model.modelPack.isInstalled {
                Text("Download the garment model to enable automatic live detection. Manual capture still works.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.horizontal, 26)
                    .padding(.bottom, 14)
            }

            if let confirmationText {
                Text(confirmationText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.58), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 12)
            }

            if captureMode == .live, model.modelPack.isInstalled {
                Label(guidance.title, systemImage: guidance.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.black.opacity(0.54), in: Capsule())
                    .padding(.bottom, 12)
            }

            bottomControls
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
    }

    private var topBar: some View {
        HStack {
            cameraButton(icon: "xmark", label: "Close camera") {
                dismiss()
            }

            Spacer()

            VStack(spacing: 2) {
                Text(captureMode == .photo ? "PHOTO" : "LIVE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                if captureMode == .live, model.settings.liveAutoCaptureEnabled {
                    Text("AUTO")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(.black.opacity(0.32), in: Capsule())

            Spacer()

            cameraButton(
                icon: camera.flashEnabled ? "bolt.fill" : "bolt.slash",
                label: camera.flashEnabled ? "Turn flash off" : "Turn flash on"
            ) {
                camera.flashEnabled.toggle()
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 24) {
                modeButton("Photo", mode: .photo)
                modeButton("Live", mode: .live)
            }

            HStack {
                if captureMode == .live {
                    cameraButton(
                        icon: model.settings.liveAutoCaptureEnabled
                            ? "bolt.badge.automatic.fill"
                            : "bolt.badge.automatic",
                        label: "Toggle automatic live capture"
                    ) {
                        model.settings.liveAutoCaptureEnabled.toggle()
                    }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }

                Spacer()

                Button {
                    capture(automatic: false)
                } label: {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(.white)
                        .frame(width: 78, height: 60)
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                                .padding(7)
                        }
                }
                .buttonStyle(CameraShutterButtonStyle())
                .disabled(!camera.isReady || camera.isCapturingPhoto || model.isAnalyzingCapture)
                .accessibilityLabel("Capture fashion photo")

                Spacer()

                cameraButton(
                    icon: "arrow.triangle.2.circlepath.camera",
                    label: "Switch camera"
                ) {
                    Task { await camera.switchCamera() }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var processingNotice: some View {
        VStack {
            Spacer()
            HStack(spacing: 11) {
                ProgressView()
                    .tint(.white)
                Text(model.captureStatus ?? "Preparing capture")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(.black.opacity(0.7), in: Capsule())
            .padding(.bottom, 154)
        }
        .transition(.opacity)
    }

    private func modeButton(_ title: String, mode: CaptureMode) -> some View {
        Button {
            captureMode = mode
        } label: {
            VStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(captureMode == mode ? .semibold : .regular))
                Capsule()
                    .fill(captureMode == mode ? Color.white : Color.clear)
                    .frame(width: 18, height: 2)
            }
            .foregroundStyle(captureMode == mode ? .white : .white.opacity(0.55))
        }
        .buttonStyle(.plain)
    }

    private func cameraButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(.white)
                .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func capture(automatic: Bool) {
        guard captureTask == nil else { return }
        captureTask = Task {
            defer { captureTask = nil }
            let data: Data?
            if automatic {
                data = bestFrameData
                lastAutomaticCapture = .now
                stableFrameCount = 0
                bestFrameData = nil
                bestFrameScore = 0
            } else {
                data = await camera.capturePhoto()
            }
            guard let data else { return }
            let scan = await model.processCapture(
                imageData: data,
                origin: .camera,
                mode: captureMode
            )
            guard let scan else {
                if model.captureStatus == "Already in Library" {
                    withAnimation(StylezamMotion.quickSpring) {
                        confirmationText = "Already in Library"
                    }
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation(.easeOut(duration: 0.2)) {
                        confirmationText = nil
                    }
                }
                return
            }
            let count = scan.items.count
            withAnimation(StylezamMotion.quickSpring) {
                let prefix = automatic ? "Auto-saved" : "Saved"
                confirmationText = count == 1
                    ? "\(prefix) 1 piece"
                    : "\(prefix) \(count) pieces"
            }
            lastAutomaticCapture = .now
            stableFrameCount = 0
            bestFrameData = nil
            bestFrameScore = 0
            if captureMode == .photo {
                try? await Task.sleep(for: .milliseconds(260))
                dismiss()
            } else {
                try? await Task.sleep(for: .seconds(1.7))
                withAnimation(.easeOut(duration: 0.2)) {
                    confirmationText = nil
                }
            }
        }
    }

    private func handlePreviewFrame(_ data: Data, aspectRatio: CGFloat) {
        guard captureMode == .live,
              model.modelPack.isInstalled,
              !isAnalyzingPreview,
              !model.isAnalyzingCapture
        else { return }
        isAnalyzingPreview = true
        frameAspectRatio = aspectRatio
        previewTask = Task {
            defer { isAnalyzingPreview = false }
            let preview = await model.previewGarments(in: data)
            guard !Task.isCancelled else { return }
            guard let preview else { return }
            candidates = preview.candidates
            guidance = preview.guidance
            assessStability(preview, frameData: data)
        }
    }

    private func assessStability(_ preview: LiveGarmentPreview, frameData: Data) {
        let found = preview.candidates
        guard !found.isEmpty else {
            stableFrameCount = 0
            stableSignature = ""
            bestFrameData = nil
            bestFrameScore = 0
            return
        }
        let signature = found
            .map {
                let x = Int(($0.box.x * 12).rounded())
                let y = Int(($0.box.y * 12).rounded())
                let width = Int(($0.box.width * 12).rounded())
                let height = Int(($0.box.height * 12).rounded())
                return "\($0.localLabel):\(x):\(y):\(width):\(height)"
            }
            .sorted()
            .joined(separator: "|")
        if signature == stableSignature {
            stableFrameCount += 1
        } else {
            stableSignature = signature
            stableFrameCount = 1
            bestFrameData = nil
            bestFrameScore = 0
        }
        if preview.qualityScore > bestFrameScore {
            bestFrameData = frameData
            bestFrameScore = preview.qualityScore
        }
        guard model.settings.liveAutoCaptureEnabled,
              preview.guidance == .ready,
              stableFrameCount >= 3,
              bestFrameScore >= 0.46,
              Date.now.timeIntervalSince(lastAutomaticCapture) >= 5
        else { return }
        capture(automatic: true)
    }

    private func updateLiveFrames() {
        camera.setLiveFramesEnabled(
            captureMode == .live && model.modelPack.isInstalled
        )
    }

    private func unavailableCamera(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 36, weight: .regular))
            Text("Camera unavailable")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.64))
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 36)
    }
}

private struct GarmentGuideOverlay: View {
    let candidates: [GarmentCandidate]
    let sourceAspectRatio: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let sourceSize = CGSize(width: max(0.01, sourceAspectRatio), height: 1)
            let scale = max(
                proxy.size.width / sourceSize.width,
                proxy.size.height / sourceSize.height
            )
            let rendered = CGSize(
                width: sourceSize.width * scale,
                height: sourceSize.height * scale
            )
            let offset = CGPoint(
                x: (proxy.size.width - rendered.width) / 2,
                y: (proxy.size.height - rendered.height) / 2
            )

            ForEach(candidates) { candidate in
                let rect = CGRect(
                    x: offset.x + candidate.box.x * rendered.width,
                    y: offset.y + candidate.box.y * rendered.height,
                    width: candidate.box.width * rendered.width,
                    height: candidate.box.height * rendered.height
                )
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    Text(candidate.localLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white, in: Capsule())
                        .position(x: rect.minX + 48, y: rect.minY + 16)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: candidates)
    }
}

private struct CameraShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
