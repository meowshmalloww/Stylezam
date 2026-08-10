@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Observation
import UIKit

struct CameraZoomCapabilities: Sendable {
    let minimum: CGFloat
    let maximum: CGFloat
    let current: CGFloat
}

@MainActor
@Observable
final class CameraSessionController {
    private(set) var isReady = false
    private(set) var isRunning = false
    private(set) var isCapturingPhoto = false
    private(set) var errorMessage: String?
    private(set) var position: AVCaptureDevice.Position
    private(set) var zoomFactor: CGFloat = 1
    private(set) var minimumZoomFactor: CGFloat = 1
    private(set) var maximumZoomFactor: CGFloat = 1
    var flashEnabled = false
    var onPreviewFrame: ((Data, CGFloat) -> Void)?

    @ObservationIgnored let driver = CameraSessionDriver()

    init(position: AVCaptureDevice.Position = .back) {
        self.position = position
    }

    func start() async {
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }
        guard authorized else {
            errorMessage = "Camera access is off. Enable it in iPhone Settings to capture a look."
            return
        }
        do {
            applyZoomCapabilities(try await driver.configure(position: position))
            driver.previewFrameHandler = { [weak self] data, aspectRatio in
                Task { @MainActor [weak self] in
                    self?.onPreviewFrame?(data, aspectRatio)
                }
            }
            try await driver.startRunning()
            isReady = true
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        driver.setLiveFramesEnabled(false)
        driver.stopRunning()
        isRunning = false
    }

    func setLiveFramesEnabled(_ enabled: Bool) {
        driver.setLiveFramesEnabled(enabled)
    }

    func switchCamera() async {
        guard !isCapturingPhoto else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        do {
            applyZoomCapabilities(try await driver.configure(position: next))
            position = next
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var availableZoomPresets: [CGFloat] {
        let candidates: [CGFloat] = [minimumZoomFactor, 1, 2, 3]
        var values: [CGFloat] = []
        for candidate in candidates where candidate >= minimumZoomFactor - 0.01
            && candidate <= maximumZoomFactor + 0.01
        {
            let normalized = (candidate * 10).rounded() / 10
            if !values.contains(where: { abs($0 - normalized) < 0.05 }) {
                values.append(normalized)
            }
        }
        return values.sorted()
    }

    func setZoomFactor(_ factor: CGFloat) {
        guard minimumZoomFactor <= maximumZoomFactor else { return }
        let clamped = min(maximumZoomFactor, max(minimumZoomFactor, factor))
        zoomFactor = clamped
        driver.setZoomFactor(clamped)
    }

    func capturePhoto() async -> Data? {
        guard isReady, !isCapturingPhoto else { return nil }
        isCapturingPhoto = true
        defer { isCapturingPhoto = false }
        do {
            let raw = try await driver.capturePhoto(flashEnabled: flashEnabled)
            return await ImageEncoding.normalizedJPEGAsync(from: raw)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func applyZoomCapabilities(_ capabilities: CameraZoomCapabilities) {
        minimumZoomFactor = capabilities.minimum
        maximumZoomFactor = capabilities.maximum
        zoomFactor = capabilities.current
    }
}

enum CameraSessionError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case captureInProgress
    case captureUnavailable
    case photoDataUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "No camera is available on this iPhone."
        case .cannotAddInput: "Stylezam could not connect to the selected camera."
        case .cannotAddOutput: "Stylezam could not prepare photo capture."
        case .captureInProgress: "The camera is already saving a photo."
        case .captureUnavailable: "The camera is not ready to save a photo yet. Hold still and try again."
        case .photoDataUnavailable: "The captured photo could not be read."
        }
    }
}

final class CameraSessionDriver: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    var previewFrameHandler: (@Sendable (Data, CGFloat) -> Void)?

    private let sessionQueue = DispatchQueue(
        label: "com.stylezam.camera.session",
        qos: .userInitiated
    )
    private let videoQueue = DispatchQueue(
        label: "com.stylezam.camera.frames",
        qos: .utility
    )
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let stateLock = NSLock()
    private var currentInput: AVCaptureDeviceInput?
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var liveFramesEnabled = false
    private var lastFrameAt: TimeInterval = 0
    private var outputsConfigured = false
    private var currentRotationAngle: CGFloat = 90

    func configure(position: AVCaptureDevice.Position) async throws -> CameraZoomCapabilities {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    continuation.resume(returning: try configureOnQueue(position: position))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startRunning() async throws {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
    }

    func stopRunning() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func setLiveFramesEnabled(_ enabled: Bool) {
        stateLock.withLock {
            liveFramesEnabled = enabled
            lastFrameAt = 0
        }
    }

    func setVideoRotationAngle(_ angle: CGFloat) {
        sessionQueue.async { [self] in
            currentRotationAngle = angle
            updateConnectionsOnQueue()
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [self] in
            guard let device = currentInput?.device else { return }
            let displayMultiplier = max(0.01, device.displayVideoZoomFactorMultiplier)
            let requestedDeviceFactor = factor / displayMultiplier
            let upperBound = min(
                device.maxAvailableVideoZoomFactor,
                10 / displayMultiplier
            )
            let clamped = min(
                upperBound,
                max(device.minAvailableVideoZoomFactor, requestedDeviceFactor)
            )
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                return
            }
        }
    }

    func capturePhoto(flashEnabled: Bool) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                let accepted = stateLock.withLock { () -> Bool in
                    guard photoContinuation == nil else { return false }
                    photoContinuation = continuation
                    return true
                }
                guard accepted else {
                    continuation.resume(throwing: CameraSessionError.captureInProgress)
                    return
                }
                guard session.isRunning,
                      session.outputs.contains(where: { $0 === photoOutput }),
                      photoOutput.captureReadiness == .ready,
                      let connection = photoOutput.connection(with: .video),
                      connection.isActive,
                      connection.isEnabled
                else {
                    finishPhotoCapture(.failure(CameraSessionError.captureUnavailable))
                    return
                }
                let settings = AVCapturePhotoSettings()
                if let device = currentInput?.device, device.hasFlash {
                    settings.flashMode = flashEnabled ? .on : .off
                }
                // AVFoundation raises an Objective-C exception—not a Swift
                // error—when this exceeds the output maximum. Match the value
                // configured before the session started.
                settings.photoQualityPrioritization = photoOutput.maxPhotoQualityPrioritization
                if connection.isVideoRotationAngleSupported(currentRotationAngle) {
                    connection.videoRotationAngle = currentRotationAngle
                }
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureOnQueue(
        position: AVCaptureDevice.Position
    ) throws -> CameraZoomCapabilities {
        let preferredTypes: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        guard let device = preferredTypes.lazy.compactMap({ type in
            AVCaptureDevice.default(type, for: .video, position: position)
        }).first else {
            throw CameraSessionError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        if let currentInput {
            session.removeInput(currentInput)
        }
        guard session.canAddInput(input) else {
            throw CameraSessionError.cannotAddInput
        }
        session.addInput(input)
        currentInput = input

        // Virtual multi-camera devices use an internal factor whose visual meaning
        // can differ from the value shown by Camera. iOS 18 exposes the exact
        // multiplier needed to keep Stylezam's 0.5x/1x/2x labels honest.
        let displayMultiplier = max(0.01, device.displayVideoZoomFactorMultiplier)
        let minimumZoom = device.minAvailableVideoZoomFactor * displayMultiplier
        let maximumZoom = min(device.maxAvailableVideoZoomFactor * displayMultiplier, 10)
        let initialZoom = min(maximumZoom, max(minimumZoom, 1))
        let initialDeviceZoom = initialZoom / displayMultiplier
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(
                device.maxAvailableVideoZoomFactor,
                max(device.minAvailableVideoZoomFactor, initialDeviceZoom)
            )
            device.unlockForConfiguration()
        } catch {
            // Zoom is an enhancement; a usable camera session must not fail when a
            // particular format temporarily refuses a configuration lock.
        }

        if !outputsConfigured {
            guard session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
                throw CameraSessionError.cannotAddOutput
            }
            session.addOutput(photoOutput)
            // Live preview remains throttled, but the automatic shutter always asks
            // AVFoundation for its full quality-oriented still before segmentation.
            photoOutput.maxPhotoQualityPrioritization = .quality
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
            outputsConfigured = true
        }
        updateConnectionsOnQueue()
        return CameraZoomCapabilities(
            minimum: minimumZoom,
            maximum: maximumZoom,
            current: initialZoom
        )
    }

    private func updateConnectionsOnQueue() {
        for connection in [
            videoOutput.connection(with: .video),
            photoOutput.connection(with: .video),
        ].compactMap({ $0 }) {
            if connection.isVideoRotationAngleSupported(currentRotationAngle) {
                connection.videoRotationAngle = currentRotationAngle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = currentInput?.device.position == .front
            }
        }
    }

    private func finishPhotoCapture(_ result: Result<Data, Error>) {
        let continuation = stateLock.withLock { () -> CheckedContinuation<Data, Error>? in
            defer { photoContinuation = nil }
            return photoContinuation
        }
        guard let continuation else { return }
        switch result {
        case let .success(data): continuation.resume(returning: data)
        case let .failure(error): continuation.resume(throwing: error)
        }
    }
}

extension CameraSessionDriver: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            finishPhotoCapture(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            finishPhotoCapture(.success(data))
        } else {
            finishPhotoCapture(.failure(CameraSessionError.photoDataUnavailable))
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            finishPhotoCapture(.failure(error))
        }
    }
}

extension CameraSessionDriver: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let shouldProcess = stateLock.withLock { () -> Bool in
            guard liveFramesEnabled else { return false }
            let now = ProcessInfo.processInfo.systemUptime
            let interval: TimeInterval
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.15 : 0.82
            case .fair: interval = 1.2
            case .serious:
                // Keep Live useful under sustained use without feeding the
                // detector continuously. The compact preview and long cadence
                // let the device cool while still allowing the UI to recover
                // from what would otherwise look like a permanently stopped scan.
                interval = 2.8
            case .critical:
                // Manual capture remains available. The UI observes the thermal
                // notification and explains this temporary safety pause.
                return false
            @unknown default: interval = 1.2
            }
            guard now - lastFrameAt >= interval else { return false }
            lastFrameAt = now
            return true
        }
        guard shouldProcess,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let longestSide = CGFloat(max(width, height))
        // A 1280 px preview preserves small accessories and garment edges better
        // than the previous 960 px sample while the model still receives one
        // bounded 384 px tensor and the frame cadence remains thermally throttled.
        let scale = min(1, 1_280 / max(1, longestSide))
        let preview = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = imageContext.jpegRepresentation(
                  of: preview,
                  colorSpace: colorSpace,
                  options: [
                      kCGImageDestinationLossyCompressionQuality
                          as CIImageRepresentationOption: 0.78,
                  ]
              )
        else { return }
        previewFrameHandler?(data, CGFloat(width) / CGFloat(max(1, height)))
    }
}
