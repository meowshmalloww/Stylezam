import Foundation
import Observation

#if canImport(ScreenCaptureKit)
import CoreImage
import CoreMedia
import UIKit
@preconcurrency import ScreenCaptureKit
#endif

/// Owns the recent frames from a full-display stream the user authorizes with Apple’s picker.
///
/// The ScreenCaptureKit implementation lives in an iOS 27-only adapter below. Keeping those
/// symbols out of this public manager lets the same app continue to launch on iOS 26 when it is
/// eventually compiled with the iOS 27 SDK.
@MainActor
@Observable
final class LiveScreenCaptureManager: NSObject {
    private struct BufferedFrame {
        let capturedAt: Date
        let data: Data
    }

    private(set) var isCapturing = false
    private(set) var latestFrameData: Data?
    private(set) var latestFrameAt: Date?
    private(set) var errorMessage: String?
    private var frameBuffer: [BufferedFrame] = []

    @ObservationIgnored private let screenActivityManager = CaptureActivityManager()
    // Type-erased because the concrete adapter is unavailable to an iOS 26 runtime.
    @ObservationIgnored private var platformAdapter: AnyObject?

    nonisolated static var isSupportedBySDK: Bool {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    nonisolated static var unsupportedSummary: String {
        #if canImport(ScreenCaptureKit)
        return "Live screen capture requires iOS 27. Camera, Photos, Share, and Control Center capture remain available."
        #else
        return "Install Xcode 27 to compile iOS 27 ScreenCaptureKit support. Camera, Photos, Share, and Control Center capture remain available."
        #endif
    }

    var statusSummary: String {
        if !Self.isSupportedBySDK {
            return Self.unsupportedSummary
        }
        if isCapturing {
            if let latestFrameAt {
                return "Live screen is active. Latest authorized frame: \(latestFrameAt.formatted(date: .omitted, time: .shortened))."
            }
            return "Live screen is active and waiting for the first frame."
        }
        return "Available through Apple’s system content-sharing picker."
    }

    func consumeLatestFrame() -> Data? {
        guard isCapturing else { return nil }

        // A Control Center tap can momentarily cover the fashion content. Prefer a recent frame
        // from just before the tap, falling back to the newest authorized frame when the stream
        // has only just started.
        let preferredCutoff = Date().addingTimeInterval(-1.2)
        return frameBuffer.last(where: { $0.capturedAt <= preferredCutoff })?.data
            ?? latestFrameData
    }

    func presentSystemPicker() {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            let adapter: LiveScreenCaptureAdapter
            if let existing = platformAdapter as? LiveScreenCaptureAdapter {
                adapter = existing
            } else {
                adapter = LiveScreenCaptureAdapter(manager: self)
                platformAdapter = adapter
            }
            adapter.presentSystemPicker()
            return
        }
        #endif
        errorMessage = Self.unsupportedSummary
    }

    func stopCapture() async {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *),
           let adapter = platformAdapter as? LiveScreenCaptureAdapter
        {
            await adapter.stopCapture()
            platformAdapter = nil
            return
        }
        #endif
        await captureDidStop()
    }

    fileprivate func prepareForStreamStart() {
        isCapturing = false
        frameBuffer.removeAll(keepingCapacity: true)
        latestFrameData = nil
        latestFrameAt = nil
        errorMessage = nil
    }

    fileprivate func captureDidStart() async {
        isCapturing = true
        errorMessage = nil
        await screenActivityManager.start(
            id: UUID().uuidString,
            source: "Authorized full display",
            phase: "Live screen active"
        )
    }

    fileprivate func captureDidStop() async {
        isCapturing = false
        frameBuffer.removeAll(keepingCapacity: false)
        latestFrameData = nil
        latestFrameAt = nil
        errorMessage = nil
        await screenActivityManager.end(phase: "Live screen stopped")
    }

    fileprivate func captureDidFail(_ error: Error) async {
        isCapturing = false
        frameBuffer.removeAll(keepingCapacity: false)
        latestFrameData = nil
        latestFrameAt = nil
        errorMessage = error.localizedDescription
        await screenActivityManager.end(
            phase: "Live screen interrupted",
            failed: true
        )
    }

    fileprivate func acceptFrame(_ data: Data) {
        guard isCapturing else { return }
        let capturedAt = Date.now
        latestFrameData = data
        latestFrameAt = capturedAt
        frameBuffer.append(BufferedFrame(capturedAt: capturedAt, data: data))
        let retentionCutoff = capturedAt.addingTimeInterval(-4)
        frameBuffer.removeAll { $0.capturedAt < retentionCutoff }
        if frameBuffer.count > 6 {
            frameBuffer.removeFirst(frameBuffer.count - 6)
        }
    }
}

#if canImport(ScreenCaptureKit)
private final class LiveScreenFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastFrameTime: TimeInterval = 0

    func shouldEncodeFrame(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lock.withLock {
            guard now - lastFrameTime >= 0.8 else { return false }
            lastFrameTime = now
            return true
        }
    }
}

@available(iOS 27.0, *)
private final class LiveScreenCaptureAdapter: NSObject,
    SCStreamOutput,
    SCStreamDelegate,
    SCContentSharingPickerObserver,
    @unchecked Sendable
{
    private weak var manager: LiveScreenCaptureManager?
    private let picker = SCContentSharingPicker.shared
    private var stream: SCStream?
    private let frameGate = LiveScreenFrameGate()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let sampleQueue = DispatchQueue(
        label: "com.stylezam.live-screen.frames",
        qos: .userInitiated
    )

    init(manager: LiveScreenCaptureManager) {
        self.manager = manager
        super.init()
    }

    @MainActor
    func presentSystemPicker() {
        guard picker.isAvailable else {
            manager?.errorMessage = "Screen capture is not available on this device or is restricted by system policy."
            return
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        picker.defaultConfiguration = configuration
        if !picker.isActive {
            picker.add(self)
            picker.isActive = true
        }
        manager?.errorMessage = nil
        picker.present()
    }

    @MainActor
    func startCapture(with filter: SCContentFilter) async {
        await tearDownStream()
        manager?.prepareForStreamStart()
        let configuration = SCStreamConfiguration()
        do {
            let newStream = SCStream(
                filter: filter,
                configuration: configuration,
                delegate: self
            )
            try newStream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: sampleQueue
            )
            try await newStream.startCapture()
            stream = newStream
            await manager?.captureDidStart()
        } catch {
            await manager?.captureDidFail(error)
        }
    }

    @MainActor
    func stopCapture() async {
        await tearDownStream()
        picker.isActive = false
        picker.remove(self)
        await manager?.captureDidStop()
    }

    @MainActor
    private func tearDownStream() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              frameGate.shouldEncodeFrame(),
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.78)
        else { return }

        Task { @MainActor [weak manager] in
            manager?.acceptFrame(data)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self, weak manager] in
            self?.stream = nil
            await manager?.captureDidFail(error)
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            await self?.startCapture(with: filter)
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {}

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak manager] in
            manager?.errorMessage = error.localizedDescription
        }
    }
}
#endif
