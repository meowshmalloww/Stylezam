import Foundation
import Observation
import OSLog

#if canImport(ScreenCaptureKit)
import CoreImage
import CoreMedia
import ImageIO
@preconcurrency import ScreenCaptureKit
#endif

struct LiveScreenFrame: Sendable {
    let capturedAt: Date
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Owns the recent frames from a full-display stream the user authorizes with Apple’s picker.
///
/// The ScreenCaptureKit implementation lives in an iOS 27-only adapter below. Keeping those
/// symbols out of this public manager lets the same app continue to launch on iOS 18–26 when it is
/// eventually compiled with the iOS 27 SDK.
@MainActor
@Observable
final class LiveScreenCaptureManager: NSObject {
    private(set) var isCapturing = false
    private(set) var latestFrameData: Data?
    private(set) var latestFrameAt: Date?
    private(set) var latestFramePixelWidth = 0
    private(set) var latestFramePixelHeight = 0
    private(set) var automaticAnalysisStatus: String?
    private(set) var automaticallySavedPieceCount = 0
    private(set) var errorMessage: String?
    private var frameBuffer: [LiveScreenFrame] = []

    @ObservationIgnored private let screenActivityManager = CaptureActivityManager()
    // Type-erased because the concrete adapter is unavailable before an iOS 27 runtime.
    @ObservationIgnored private var platformAdapter: AnyObject?
    @ObservationIgnored private var frameHandler: (@MainActor @Sendable (LiveScreenFrame) -> Void)?

    nonisolated static var isSupportedBySDK: Bool {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    nonisolated static var unsupportedSummary: String {
        #if targetEnvironment(simulator)
        return "Live Screen must be tested on a physical iPhone running iOS 27; Apple does not include ScreenCaptureKit in the iOS Simulator SDK."
        #elseif canImport(ScreenCaptureKit)
        return "Live screen capture requires iOS 27. Camera, Photos, Share, and Control Center capture remain available."
        #else
        return "Install Xcode 27 to compile iOS 27 ScreenCaptureKit support. Camera, Photos, Share, clipboard, and normal capture remain available."
        #endif
    }

    var statusSummary: String {
        if !Self.isSupportedBySDK {
            return Self.unsupportedSummary
        }
        if isCapturing {
            let resolution = latestFramePixelWidth > 0 && latestFramePixelHeight > 0
                ? " · \(latestFramePixelWidth) × \(latestFramePixelHeight)"
                : ""
            if let automaticAnalysisStatus {
                return "Live screen is active\(resolution). \(automaticAnalysisStatus)"
            }
            if let latestFrameAt {
                return "Live screen is active\(resolution). Latest authorized frame: \(latestFrameAt.formatted(date: .omitted, time: .shortened))."
            }
            return "Live screen is active and waiting for the first frame."
        }
        return "Available through Apple’s system content-sharing picker."
    }

    func setFrameHandler(
        _ handler: (@MainActor @Sendable (LiveScreenFrame) -> Void)?
    ) {
        frameHandler = handler
    }

    func setAutomaticAnalysisStatus(_ status: String?) {
        automaticAnalysisStatus = status
    }

    func recordAutomaticallySavedPieces(_ count: Int) {
        automaticallySavedPieceCount += max(0, count)
        automaticAnalysisStatus = count == 1
            ? "Saved 1 detected piece automatically."
            : "Saved \(count) detected pieces automatically."
    }

    /// Slows full-resolution frame materialization after a stable page has already been handled.
    /// The stream remains authorized and periodically samples for a visual change.
    func setAutomaticAnalysisIdle(_ idle: Bool) {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *),
           let adapter = platformAdapter as? LiveScreenCaptureAdapter
        {
            adapter.setAnalysisIdle(idle)
        }
        #endif
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
        latestFramePixelWidth = 0
        latestFramePixelHeight = 0
        automaticAnalysisStatus = "Waiting for a stable fashion item."
        automaticallySavedPieceCount = 0
        errorMessage = nil
    }

    fileprivate func setPickerError(_ message: String?) {
        errorMessage = message
    }

    fileprivate func captureDidStart() async {
        isCapturing = true
        automaticAnalysisStatus = "Watching for a stable fashion item."
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
        latestFramePixelWidth = 0
        latestFramePixelHeight = 0
        automaticAnalysisStatus = nil
        errorMessage = nil
        await screenActivityManager.end(phase: "Live screen stopped")
    }

    fileprivate func captureDidFail(_ error: Error) async {
        isCapturing = false
        frameBuffer.removeAll(keepingCapacity: false)
        latestFrameData = nil
        latestFrameAt = nil
        latestFramePixelWidth = 0
        latestFramePixelHeight = 0
        automaticAnalysisStatus = nil
        errorMessage = error.localizedDescription
        await screenActivityManager.end(
            phase: "Live screen interrupted",
            failed: true
        )
    }

    fileprivate func acceptFrame(
        _ data: Data,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        guard isCapturing else { return }
        let capturedAt = Date.now
        let frame = LiveScreenFrame(
            capturedAt: capturedAt,
            data: data,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
        latestFrameData = data
        latestFrameAt = capturedAt
        latestFramePixelWidth = pixelWidth
        latestFramePixelHeight = pixelHeight
        frameBuffer.append(frame)
        let retentionCutoff = capturedAt.addingTimeInterval(-4)
        frameBuffer.removeAll { $0.capturedAt < retentionCutoff }
        if frameBuffer.count > 6 {
            frameBuffer.removeFirst(frameBuffer.count - 6)
        }
        frameHandler?(frame)
    }
}

#if canImport(ScreenCaptureKit)
private final class LiveScreenFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastFrameTime: TimeInterval = 0
    private var analysisIdle = false

    func setAnalysisIdle(_ idle: Bool) {
        lock.withLock {
            guard analysisIdle != idle else { return }
            analysisIdle = idle
            // Let a newly active detector accept the next available frame immediately.
            if !idle { lastFrameTime = 0 }
        }
    }

    func shouldEncodeFrame(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lock.withLock {
            let processInfo = ProcessInfo.processInfo
            let interval: TimeInterval
            switch processInfo.thermalState {
            case .nominal:
                if analysisIdle {
                    interval = processInfo.isLowPowerModeEnabled ? 7.0 : 4.0
                } else {
                    interval = processInfo.isLowPowerModeEnabled ? 2.4 : 1.45
                }
            case .fair:
                interval = analysisIdle ? 6.0 : 2.2
            case .serious, .critical:
                return false
            @unknown default:
                interval = 1.4
            }
            guard now - lastFrameTime >= interval else { return false }
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
    private static let logger = Logger(
        subsystem: "com.stylezam.app",
        category: "LiveScreen"
    )
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
            manager?.setPickerError(
                "Screen capture is not available on this device or is restricted by system policy."
            )
            return
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        picker.defaultConfiguration = configuration
        if !picker.isActive {
            picker.add(self)
            picker.isActive = true
        }
        manager?.setPickerError(nil)
        picker.present()
    }

    @MainActor
    func startCapture(with filter: SCContentFilter) async {
        await tearDownStream()
        frameGate.setAnalysisIdle(false)
        manager?.prepareForStreamStart()
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
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
            Self.logger.notice("Authorized full-display stream started")
            await manager?.captureDidStart()
        } catch {
            Self.logger.error(
                "Unable to start authorized stream: \(error.localizedDescription, privacy: .public)"
            )
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

    nonisolated func setAnalysisIdle(_ idle: Bool) {
        frameGate.setAnalysisIdle(idle)
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
              Self.isUsableFrame(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(
            Self.videoOrientation(for: sampleBuffer)
        )
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = imageContext.jpegRepresentation(
                  of: image,
                  colorSpace: colorSpace,
                  options: [
                      kCGImageDestinationLossyCompressionQuality
                          as CIImageRepresentationOption: 0.92,
                  ]
              )
        else { return }

        let width = Int(image.extent.width.rounded())
        let height = Int(image.extent.height.rounded())
        Self.logger.debug("Accepted authorized frame \(width)x\(height)")

        Task { @MainActor [weak manager] in
            manager?.acceptFrame(
                data,
                pixelWidth: width,
                pixelHeight: height
            )
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self, weak manager] in
            self?.stream = nil
            Self.logger.error(
                "Authorized stream stopped: \(error.localizedDescription, privacy: .public)"
            )
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
            manager?.setPickerError(error.localizedDescription)
        }
    }

    private nonisolated static func attachments(
        for sampleBuffer: CMSampleBuffer
    ) -> [SCStreamFrameInfo: Any]? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]]
        else { return nil }
        return attachments.first
    }

    private nonisolated static func isUsableFrame(
        _ sampleBuffer: CMSampleBuffer
    ) -> Bool {
        guard let attachments = attachments(for: sampleBuffer),
              let rawStatus = attachments[.status] as? NSNumber,
              let status = SCFrameStatus(rawValue: rawStatus.intValue)
        else {
            // Some early beta builds omit status metadata on otherwise valid frames.
            return true
        }
        return status == .complete || status == .started
    }

    private nonisolated static func videoOrientation(
        for sampleBuffer: CMSampleBuffer
    ) -> CGImagePropertyOrientation {
        guard let attachments = attachments(for: sampleBuffer),
              let rawOrientation = attachments[.videoOrientation] as? NSNumber,
              let orientation = CGImagePropertyOrientation(
                  rawValue: rawOrientation.uint32Value
              )
        else { return .up }
        return orientation
    }
}
#endif
