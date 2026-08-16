import SwiftUI
import UIKit

struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraSessionController()
    @State private var captureMode: CaptureMode = .photo
    @State private var candidates: [GarmentCandidate] = []
    @State private var provisionalCandidates: [GarmentCandidate] = []
    @State private var guidance: LiveCaptureGuidance = .aimAtFashion
    @State private var frameAspectRatio: CGFloat = 9 / 16
    @State private var isAnalyzingPreview = false
    @State private var previewTask: Task<Void, Never>?
    @State private var stableSignature = ""
    @State private var stableFrameCount = 0
    @State private var bestFrameData: Data?
    @State private var bestFrameScore = 0.0
    @State private var livePreviewStabilizer = LivePreviewStabilizer()
    @State private var lastAutomaticCapture = Date.distantPast
    @State private var confirmationText: String?
    @State private var captureTask: Task<Void, Never>?
    @State private var currentLiveContentFingerprint: LiveScreenContentFingerprint?
    @State private var suppressedLiveContentFingerprint: LiveScreenContentFingerprint?
    @State private var liveInferenceGate = LiveContentInferenceGate()
    @State private var zoomGestureAnchor: CGFloat?
    @State private var thermalState = ProcessInfo.processInfo.thermalState

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

                GarmentGuideOverlay(
                    candidates: candidates,
                    provisionalCandidates: provisionalCandidates,
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

            cameraLegibilityGradient
                .allowsHitTesting(false)

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
            // Live is deliberately hands-free. Entering it restores automatic
            // saving so a previously paused debug setting cannot turn it back
            // into a manual camera on a real device.
            if captureMode == .live {
                model.settings.liveAutoCaptureEnabled = true
            }
            previewTask?.cancel()
            isAnalyzingPreview = false
            candidates = []
            provisionalCandidates = []
            guidance = .aimAtFashion
            stableSignature = ""
            stableFrameCount = 0
            bestFrameData = nil
            bestFrameScore = 0
            currentLiveContentFingerprint = nil
            suppressedLiveContentFingerprint = nil
            liveInferenceGate.reset()
            livePreviewStabilizer.reset()
            updateLiveFrames()
        }
        .onChange(of: model.modelPack.isInstalled) { _, _ in
            updateLiveFrames()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ProcessInfo.thermalStateDidChangeNotification
            )
        ) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
        .onDisappear {
            previewTask?.cancel()
            captureTask?.cancel()
            camera.stop()
        }
    }

    private var cameraChrome: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                landscapeCameraChrome
            } else {
                portraitCameraChrome
            }
        }
    }

    private var portraitCameraChrome: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 12)

            Spacer()

            liveStatus
                .padding(.bottom, 12)

            bottomControls
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
    }

    private var landscapeCameraChrome: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 22)
                .padding(.top, 8)

            Spacer()

            HStack(alignment: .bottom, spacing: 22) {
                liveStatus
                    .frame(maxWidth: 360, alignment: .leading)

                Spacer(minLength: 0)

                bottomControls
                    .frame(width: 330)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var liveStatus: some View {
        if !model.modelPack.isInstalled {
            Text(captureMode == .live
                ? "Live detection is unavailable. You can still take a photo."
                : "Recognition boxes are unavailable until the on-device model is ready.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.horizontal, 22)
        }

        if let confirmationText {
            Label(confirmationText, systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if model.modelPack.isInstalled {
            if captureMode == .live {
                liveGuidance
            } else {
                photoRecognitionGuidance
            }
        }
    }

    private var cameraLegibilityGradient: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.42), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 132)

            Spacer()

            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            cameraToolButton(icon: "xmark", label: "Close camera") {
                dismiss()
            }

            Spacer()

            HStack(spacing: 7) {
                if captureMode == .live {
                    Circle()
                        .fill(model.settings.liveAutoCaptureEnabled ? .white : .white.opacity(0.45))
                        .frame(width: 6, height: 6)
                }
                Text(captureMode == .photo ? "Photo" : "Live scan")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.13), lineWidth: 0.5)
            }

            Spacer()

            cameraToolButton(
                icon: camera.flashEnabled ? "bolt.fill" : "bolt.slash",
                label: camera.flashEnabled ? "Turn flash off" : "Turn flash on"
            ) {
                camera.flashEnabled.toggle()
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            zoomControls
            modePicker

            HStack(alignment: .center) {
                if captureMode == .live {
                    cameraToolButton(
                        icon: model.settings.liveAutoCaptureEnabled
                            ? "pause.fill"
                            : "play.fill",
                        label: model.settings.liveAutoCaptureEnabled
                            ? "Pause automatic live saving"
                            : "Resume automatic live saving"
                    ) {
                        model.settings.liveAutoCaptureEnabled.toggle()
                    }
                } else {
                    Color.clear.frame(width: 48, height: 48)
                }

                Spacer()

                if captureMode == .live {
                    liveAutomaticSaveIndicator
                } else {
                    Button {
                        capture(automatic: false)
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.96), lineWidth: 4)
                                .frame(width: 82, height: 82)
                            Circle()
                                .fill(.white)
                                .frame(width: 68, height: 68)
                        }
                    }
                    .buttonStyle(CameraShutterButtonStyle())
                    .disabled(!camera.isReady || camera.isCapturingPhoto || model.isAnalyzingCapture)
                    .accessibilityLabel("Capture recognized fashion photo")
                }

                Spacer()

                cameraToolButton(
                    icon: "camera.rotate",
                    label: "Switch camera"
                ) {
                    Task { await camera.switchCamera() }
                }
            }
        }
        .foregroundStyle(.white)
    }

    /// Live camera never exposes a manual shutter: recognition is temporal and
    /// the full-quality still is requested only once a box remains stable.
    private var liveAutomaticSaveIndicator: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.94), lineWidth: 3)
                    .frame(width: 82, height: 82)
                Circle()
                    .fill(.white.opacity(model.settings.liveAutoCaptureEnabled ? 0.96 : 0.24))
                    .frame(width: 68, height: 68)
                Image(systemName: model.settings.liveAutoCaptureEnabled
                    ? "bolt.badge.automatic.fill"
                    : "pause.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(model.settings.liveAutoCaptureEnabled ? .black : .white)
            }
            Text(model.settings.liveAutoCaptureEnabled ? "AUTO" : "PAUSED")
                .font(.caption2.weight(.bold))
                .tracking(0.9)
        }
        .frame(width: 94, height: 104)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            model.settings.liveAutoCaptureEnabled
                ? "Automatic live saving is active"
                : "Automatic live saving is paused"
        )
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

    private var modePicker: some View {
        HStack(spacing: 3) {
            modeButton("Photo", mode: .photo)
            modeButton("Live", mode: .live)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    private var liveGuidance: some View {
        let copy = liveGuidanceCopy
        return HStack(spacing: 12) {
            Image(systemName: copy.symbol)
                .font(.body.weight(.semibold))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.title)
                    .font(.subheadline.weight(.semibold))
                Text(copy.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if !provisionalCandidates.isEmpty {
                Text("\(provisionalCandidates.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 390)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .padding(.horizontal, 22)
    }

    private var liveGuidanceCopy: (symbol: String, title: String, detail: String) {
        if thermalState == .critical {
            return (
                "thermometer.high",
                "Live scan is cooling down",
                "The camera stays available. Detection resumes automatically when the iPhone cools."
            )
        }
        if thermalState == .serious {
            return (
                "thermometer.medium",
                "Live scan is reducing activity",
                "Detection continues at a slower cadence to lower heat."
            )
        }
        if !model.settings.liveAutoCaptureEnabled {
            return (
                "pause.circle",
                "Automatic saving paused",
                "Recognition boxes still update. Resume when you want Live scans saved automatically."
            )
        }
        if provisionalCandidates.isEmpty {
            return ("viewfinder", "Aim at a fashion item", "Include the full piece and keep it inside the frame.")
        }
        if candidates.isEmpty {
            let count = provisionalCandidates.count
            return ("scope", "Confirming \(count) piece\(count == 1 ? "" : "s")", "Hold steady while Stylezam confirms the labels.")
        }
        if guidance == .ready {
            return ("checkmark.circle", "Ready to save", "Hold still. Stylezam will capture this look automatically.")
        }
        return (guidance.symbol, guidance.title, "Keep the detected pieces visible for automatic capture.")
    }

    private var photoRecognitionGuidance: some View {
        let title: String
        let detail: String
        let symbol: String
        if provisionalCandidates.isEmpty {
            title = "Recognition is on"
            detail = "Aim at a fashion item. A box means Stylezam can recognize it before you take the photo."
            symbol = "viewfinder"
        } else if candidates.isEmpty {
            title = "Confirming the item"
            detail = "Hold still briefly. Dashed boxes are still being verified on this iPhone."
            symbol = "scope"
        } else {
            let count = candidates.count
            title = "\(count) piece\(count == 1 ? "" : "s") recognized"
            detail = "The solid box is ready. Tap the shutter to save this photo and its detected pieces."
            symbol = "checkmark.circle"
        }

        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 390)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .padding(.horizontal, 22)
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
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 176)
        }
        .transition(.opacity)
    }

    private func modeButton(_ title: String, mode: CaptureMode) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                captureMode = mode
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(captureMode == mode ? .black : .white.opacity(0.68))
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(
                    captureMode == mode ? Color.white : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func cameraToolButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(.white)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.13), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func capture(automatic: Bool) {
        // Photo mode is intentionally manual. Live mode reaches this method
        // only through its temporal auto-save gate.
        let mode = captureMode
        guard automatic ? mode == .live : mode == .photo else { return }
        guard captureTask == nil else { return }
        captureTask = Task {
            camera.setLiveFramesEnabled(false)
            previewTask?.cancel()
            isAnalyzingPreview = false
            defer {
                captureTask = nil
                updateLiveFrames()
            }
            let data: Data?
            if automatic {
                let previewFallback = bestFrameData
                // Preview frames are intentionally compact. Once the view is
                // stable, ask AVFoundation for a full-quality still so the
                // saved scan and its crops do not inherit preview resolution.
                data = await camera.capturePhoto() ?? previewFallback
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
                mode: mode
            )
            guard let scan else {
                if mode == .live, model.captureStatus == "Already in Library" {
                    suppressedLiveContentFingerprint = currentLiveContentFingerprint
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
            if mode == .live {
                suppressedLiveContentFingerprint = currentLiveContentFingerprint
            }
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
            if mode == .photo {
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
        guard model.modelPack.isInstalled,
              !isAnalyzingPreview,
              !model.isAnalyzingCapture
        else { return }
        isAnalyzingPreview = true
        frameAspectRatio = aspectRatio
        let mode = captureMode
        previewTask = Task {
            defer { isAnalyzingPreview = false }

            // Photo mode deliberately gets the same lightweight box preview as
            // Live mode, but avoids perceptual duplicate work because a user
            // still chooses exactly when to capture. The heavier duplicate guard
            // remains exclusive to automatic Live saves.
            if mode == .live {
                let contentFingerprint = await Task.detached(priority: .utility) {
                    LiveScreenContentFingerprint.make(imageData: data)
                }.value
                guard !Task.isCancelled else { return }
                currentLiveContentFingerprint = contentFingerprint
                if let contentFingerprint,
                   let suppressed = suppressedLiveContentFingerprint,
                   contentFingerprint.isVisuallySimilar(to: suppressed)
                {
                    // The accepted still is already saved. Keep the camera fluid
                    // without repeatedly running Core ML on an unchanged view.
                    return
                }
                if suppressedLiveContentFingerprint != nil {
                    suppressedLiveContentFingerprint = nil
                    stableFrameCount = 0
                    stableSignature = ""
                    bestFrameData = nil
                    bestFrameScore = 0
                    livePreviewStabilizer.reset()
                    liveInferenceGate.reset()
                }
                if let contentFingerprint,
                   !liveInferenceGate.shouldAnalyze(fingerprint: contentFingerprint)
                {
                    return
                }
            }

            let preview = await model.previewGarments(in: data)
            guard !Task.isCancelled else { return }
            guard let preview else { return }
            if mode == .live {
                liveInferenceGate.recordResult(hasCandidates: !preview.candidates.isEmpty)
            }
            provisionalCandidates = preview.candidates
            let stabilizedCandidates = livePreviewStabilizer.update(
                with: preview.candidates
            )
            let stabilizedPreview = LiveGarmentPreview(
                candidates: stabilizedCandidates,
                qualityScore: preview.qualityScore,
                guidance: stabilizedCandidates.isEmpty && !preview.candidates.isEmpty
                    ? .holdStill
                    : preview.guidance
            )
            candidates = stabilizedPreview.candidates
            guidance = stabilizedPreview.guidance
            if mode == .live {
                assessStability(stabilizedPreview, frameData: data)
            }
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
        guard let anchor = found.max(by: { $0.confidence < $1.confidence }) else { return }
        // Use the strongest confirmed piece to judge camera stability. The
        // full-resolution capture still detects and saves every visible piece.
        let signature = "\(anchor.id):\(anchor.localLabel)"
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
              // LivePreviewStabilizer has already required two matching detector frames before
              // this method receives a candidate. One additional stabilized observation used to
              // make automatic capture wait for a third inference with no accuracy benefit.
              stableFrameCount >= 1,
              bestFrameScore >= 0.40,
              Date.now.timeIntervalSince(lastAutomaticCapture) >= 5
        else { return }
        capture(automatic: true)
    }

    private func updateLiveFrames() {
        camera.setLiveFramesEnabled(
            model.modelPack.isInstalled
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
                .stylezamGlassButton(prominent: true)
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
    let provisionalCandidates: [GarmentCandidate]
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

            let unconfirmed = provisionalCandidates.filter { provisional in
                !candidates.contains {
                    Self.intersectionOverUnion($0.box, provisional.box) > 0.5
                }
            }

            ForEach(unconfirmed) { candidate in
                let rect = renderedRect(for: candidate, rendered: rendered, offset: offset)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        .white.opacity(0.42),
                        style: StrokeStyle(lineWidth: 1.25, dash: [5, 4])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .transition(.opacity)
            }

            ForEach(candidates) { candidate in
                let rect = renderedRect(for: candidate, rendered: rendered, offset: offset)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    Text(
                        GarmentDetectionQualityPolicy.liveLabel(
                            label: candidate.localLabel,
                            confidence: candidate.confidence
                        )
                    )
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
        .animation(.easeOut(duration: 0.16), value: candidates)
        .animation(.easeOut(duration: 0.12), value: provisionalCandidates)
    }

    private func renderedRect(
        for candidate: GarmentCandidate,
        rendered: CGSize,
        offset: CGPoint
    ) -> CGRect {
        CGRect(
            x: offset.x + candidate.box.x * rendered.width,
            y: offset.y + candidate.box.y * rendered.height,
            width: candidate.box.width * rendered.width,
            height: candidate.box.height * rendered.height
        )
    }

    private static func intersectionOverUnion(
        _ left: BoundingBoxDTO,
        _ right: BoundingBoxDTO
    ) -> Double {
        let width = max(
            0,
            min(left.x + left.width, right.x + right.width) - max(left.x, right.x)
        )
        let height = max(
            0,
            min(left.y + left.height, right.y + right.height) - max(left.y, right.y)
        )
        let intersection = width * height
        guard intersection > 0 else { return 0 }
        let union = left.width * left.height + right.width * right.height - intersection
        return union > 0 ? intersection / union : 0
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

/// Lightweight temporal tracking for the live overlay. The detector remains a
/// single pass per sampled frame; this only accepts a label after it agrees on
/// the same physical region in consecutive frames. That removes most transient
/// false positives and label flicker without adding another model invocation.
private struct LivePreviewStabilizer {
    private struct Observation {
        let label: String
        let confidence: Double
    }

    private struct Track {
        let id: String
        var box: BoundingBoxDTO
        var observations: [Observation]
        var consecutiveHits: Int
        var lastSeenFrame: Int
    }

    private var frameIndex = 0
    private var tracks: [Track] = []

    mutating func reset() {
        frameIndex = 0
        tracks = []
    }

    mutating func update(with incoming: [GarmentCandidate]) -> [GarmentCandidate] {
        frameIndex += 1
        var matchedTracks = Set<Int>()

        // RF-DETR can occasionally return nearly identical boxes with two
        // competing labels. Keep the stronger one before temporal matching.
        var candidates: [GarmentCandidate] = []
        for candidate in incoming.sorted(by: { $0.confidence > $1.confidence }) {
            guard !candidates.contains(where: {
                Self.intersectionOverUnion($0.box, candidate.box) > 0.84
            }) else { continue }
            candidates.append(candidate)
        }

        for candidate in candidates {
            var bestTrackIndex: Int?
            var bestOverlap = 0.34
            for index in tracks.indices where !matchedTracks.contains(index) {
                let overlap = Self.intersectionOverUnion(tracks[index].box, candidate.box)
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestTrackIndex = index
                }
            }

            if let index = bestTrackIndex {
                let previous = tracks[index]
                tracks[index].box = Self.smoothedBox(
                    previous.box,
                    candidate.box,
                    currentWeight: 0.58
                )
                tracks[index].observations.append(
                    Observation(
                        label: candidate.localLabel,
                        confidence: candidate.confidence
                    )
                )
                tracks[index].observations = Array(tracks[index].observations.suffix(4))
                tracks[index].consecutiveHits = previous.lastSeenFrame == frameIndex - 1
                    ? previous.consecutiveHits + 1
                    : 1
                tracks[index].lastSeenFrame = frameIndex
                matchedTracks.insert(index)
            } else {
                tracks.append(
                    Track(
                        id: UUID().uuidString,
                        box: candidate.box,
                        observations: [
                            Observation(
                                label: candidate.localLabel,
                                confidence: candidate.confidence
                            )
                        ],
                        consecutiveHits: 1,
                        lastSeenFrame: frameIndex
                    )
                )
                matchedTracks.insert(tracks.count - 1)
            }
        }

        for index in tracks.indices where !matchedTracks.contains(index) {
            tracks[index].consecutiveHits = 0
        }
        tracks.removeAll { frameIndex - $0.lastSeenFrame > 1 }

        return tracks.compactMap { track in
            guard track.lastSeenFrame == frameIndex,
                  track.consecutiveHits >= 2,
                  let label = Self.consensusLabel(in: track.observations)
            else { return nil }
            let matching = track.observations.filter { $0.label == label }
            guard matching.count >= 2 else { return nil }
            let confidence = matching.map(\.confidence).reduce(0, +)
                / Double(matching.count)
            guard confidence >= 0.48 else { return nil }
            return GarmentCandidate(
                id: track.id,
                localLabel: label,
                confidence: confidence,
                box: track.box,
                boxCropData: nil,
                cropData: nil
            )
        }
        .sorted { $0.confidence > $1.confidence }
    }

    private static func consensusLabel(in observations: [Observation]) -> String? {
        let grouped = Dictionary(grouping: observations, by: \.label)
        return grouped.max { left, right in
            if left.value.count != right.value.count {
                return left.value.count < right.value.count
            }
            let leftConfidence = left.value.map(\.confidence).reduce(0, +)
            let rightConfidence = right.value.map(\.confidence).reduce(0, +)
            return leftConfidence < rightConfidence
        }?.key
    }

    private static func smoothedBox(
        _ previous: BoundingBoxDTO,
        _ current: BoundingBoxDTO,
        currentWeight: Double
    ) -> BoundingBoxDTO {
        let previousWeight = 1 - currentWeight
        return BoundingBoxDTO(
            x: previous.x * previousWeight + current.x * currentWeight,
            y: previous.y * previousWeight + current.y * currentWeight,
            width: previous.width * previousWeight + current.width * currentWeight,
            height: previous.height * previousWeight + current.height * currentWeight
        )
    }

    private static func intersectionOverUnion(
        _ left: BoundingBoxDTO,
        _ right: BoundingBoxDTO
    ) -> Double {
        let intersectionWidth = max(
            0,
            min(left.x + left.width, right.x + right.width) - max(left.x, right.x)
        )
        let intersectionHeight = max(
            0,
            min(left.y + left.height, right.y + right.height) - max(left.y, right.y)
        )
        let intersection = intersectionWidth * intersectionHeight
        guard intersection > 0 else { return 0 }
        let union = left.width * left.height + right.width * right.height - intersection
        return union > 0 ? intersection / union : 0
    }
}
