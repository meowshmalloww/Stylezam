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
    private(set) var position: AVCaptureDevice.Position = .back
    var flashEnabled = false
    var onPreviewFrame: ((Data, CGFloat) -> Void)?

    @ObservationIgnored let driver = CameraSessionDriver()

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
    case photoDataUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "No camera is available on this iPhone."
        case .cannotAddInput: "Stylezam could not connect to the selected camera."
        case .cannotAddOutput: "Stylezam could not prepare photo capture."
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
        qos: .userInitiated
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

    func capturePhoto(flashEnabled: Bool) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                stateLock.withLock {
                    photoContinuation = continuation
                }
                let settings = AVCapturePhotoSettings()
                if let device = currentInput?.device, device.hasFlash {
                    settings.flashMode = flashEnabled ? .on : .off
                }
                settings.photoQualityPrioritization = .quality
                if let connection = photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90)
                {
                    connection.videoRotationAngle = 90
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
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
            outputsConfigured = true
        }
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90)
        {
            connection.videoRotationAngle = 90
        }
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoMirroringSupported
        {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
    }
}

extension CameraSessionDriver: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let continuation = stateLock.withLock { () -> CheckedContinuation<Data, Error>? in
            defer { photoContinuation = nil }
            return photoContinuation
        }
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation.resume(returning: data)
        } else {
            continuation.resume(throwing: CameraSessionError.photoDataUnavailable)
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
            guard now - lastFrameAt >= 0.48 else { return false }
            lastFrameAt = now
            return true
        }
        guard shouldProcess,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.74)
        else { return }
        previewFrameHandler?(data, CGFloat(width) / CGFloat(max(1, height)))
    }
}
