@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraSessionController {
    private(set) var isReady = false
    private(set) var isRunning = false
    private(set) var isCapturingPhoto = false
    private(set) var errorMessage: String?
    private(set) var position: AVCaptureDevice.Position
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
            try await driver.configure(position: position)
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
            try await driver.configure(position: next)
            position = next
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

    func configure(position: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    try configureOnQueue(position: position)
                    continuation.resume()
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

    private func configureOnQueue(position: AVCaptureDevice.Position) throws {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        guard let device = discovery.devices.first else {
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

        if !outputsConfigured {
            guard session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
                throw CameraSessionError.cannotAddOutput
            }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
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
            case .serious, .critical:
                // Keep the camera and manual shutter available while pausing
                // background ML work so an already-warm phone can recover.
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
        let scale = min(1, 960 / max(1, longestSide))
        let preview = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = imageContext.createCGImage(preview, from: preview.extent),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.68)
        else { return }
        previewFrameHandler?(data, CGFloat(width) / CGFloat(max(1, height)))
    }
}
