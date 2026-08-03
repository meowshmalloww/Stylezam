import CoreImage
import CoreMedia
import Foundation
import Observation
import UIKit

#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

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

/// Owns the full-display stream that the user authorizes with Apple’s iOS 27 picker.
///
/// ScreenCaptureKit is absent from the iOS 26 SDK. Its implementation is compiled only by an SDK
/// that exposes the framework, while this public surface keeps the rest of Stylezam buildable and
/// makes the unavailable state explicit instead of simulating captured content.
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

    nonisolated private let frameGate = LiveScreenFrameGate()

    nonisolated static var isSupportedBySDK: Bool {
        #if canImport(ScreenCaptureKit)
        true
        #else
        false
        #endif
    }

    var statusSummary: String {
        if !Self.isSupportedBySDK {
            return "Install Xcode 27 to compile iOS 27 ScreenCaptureKit support. Camera, Photos, Share, and Control Center capture remain available."
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
        let preferredCutoff = Date().addingTimeInterval(-1.8)
        return frameBuffer.last(where: { $0.capturedAt <= preferredCutoff })?.data
            ?? latestFrameData
    }

    #if canImport(ScreenCaptureKit)
    private let picker = SCContentSharingPicker.shared
    private var pickerObserver: LiveScreenPickerObserver?
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(
        label: "com.stylezam.live-screen.frames",
        qos: .userInitiated
    )

    override init() {
        super.init()
        pickerObserver = LiveScreenPickerObserver(manager: self)
    }

    func presentSystemPicker() {
        guard picker.isAvailable else {
            errorMessage = "Screen capture is not available on this device or is restricted by system policy."
            return
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        picker.defaultConfiguration = configuration
        if !picker.isActive, let pickerObserver {
            picker.add(pickerObserver)
            picker.isActive = true
        }
        errorMessage = nil
        picker.present()
    }

    func startCapture(with filter: SCContentFilter) async {
        await tearDownStream()
        frameBuffer.removeAll(keepingCapacity: true)
        latestFrameData = nil
        latestFrameAt = nil
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
            isCapturing = true
            errorMessage = nil
        } catch {
            isCapturing = false
            errorMessage = error.localizedDescription
        }
    }

    func stopCapture() async {
        await tearDownStream()
        isCapturing = false
        frameBuffer.removeAll(keepingCapacity: false)
        latestFrameData = nil
        latestFrameAt = nil
        picker.isActive = false
        if let pickerObserver {
            picker.remove(pickerObserver)
        }
    }

    private func tearDownStream() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    nonisolated private func accept(_ sampleBuffer: CMSampleBuffer) {
        guard frameGate.shouldEncodeFrame(),
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(image, from: image.extent),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9)
        else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let capturedAt = Date.now
            latestFrameData = data
            latestFrameAt = capturedAt
            frameBuffer.append(BufferedFrame(capturedAt: capturedAt, data: data))
            let retentionCutoff = capturedAt.addingTimeInterval(-15)
            frameBuffer.removeAll { $0.capturedAt < retentionCutoff }
        }
    }
    #else
    func presentSystemPicker() {
        errorMessage = "Live screen capture requires the iOS 27 SDK and Xcode 27."
    }

    func stopCapture() async {}
    #endif
}

#if canImport(ScreenCaptureKit)
extension LiveScreenCaptureManager: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        accept(sampleBuffer)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isCapturing = false
            self?.errorMessage = error.localizedDescription
        }
    }
}

private final class LiveScreenPickerObserver: NSObject,
    SCContentSharingPickerObserver,
    @unchecked Sendable
{
    private weak var manager: LiveScreenCaptureManager?

    init(manager: LiveScreenCaptureManager) {
        self.manager = manager
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak manager] in
            await manager?.startCapture(with: filter)
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
