@preconcurrency import AVFAudio
import Foundation
import Observation
@preconcurrency import Speech

@MainActor
@Observable
final class OnDeviceSpeechInput {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var level: Float = 0
    private(set) var errorMessage: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""
        do {
            guard await Self.requestSpeechPermission() else {
                throw SpeechInputError.speechPermission
            }
            guard await Self.requestMicrophonePermission() else {
                throw SpeechInputError.microphonePermission
            }
            guard let recognizer = SFSpeechRecognizer(locale: .current),
                  recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition
            else { throw SpeechInputError.onDeviceUnavailable }

            recognitionTask?.cancel()
            recognitionTask = nil
            let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = true
            recognitionRequest.addsPunctuation = true
            recognitionRequest.contextualStrings = [
                "Stylezam", "garment", "outfit", "jacket", "trousers", "sneakers",
                "handbag", "bracelet", "necklace", "try on",
            ]
            request = recognitionRequest

            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                recognitionRequest.append(buffer)
                let measuredLevel = Self.normalizedLevel(buffer)
                Task { @MainActor [weak self] in self?.level = measuredLevel }
            }

            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) {
                [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        transcript = result.bestTranscription.formattedString
                        if result.isFinal { finishAudioSession() }
                    }
                    if let error, isRecording {
                        errorMessage = error.localizedDescription
                        finishAudioSession()
                    }
                }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
            finishAudioSession(cancelRecognition: true)
        }
    }

    func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func cancel() {
        transcript = ""
        finishAudioSession(cancelRecognition: true)
    }

    private func finishAudioSession(cancelRecognition: Bool = false) {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        if cancelRecognition { recognitionTask?.cancel() }
        request?.endAudio()
        recognitionTask = nil
        request = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private nonisolated static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let values = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count { sum += values[index] * values[index] }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, 0.000_01))
        return max(0, min(1, (decibels + 55) / 45))
    }

    private static func requestSpeechPermission() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
private enum SpeechInputError: LocalizedError {
    case speechPermission
    case microphonePermission
    case onDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .speechPermission:
            "Speech recognition is off. Allow it in iPhone Settings to speak a question."
        case .microphonePermission:
            "Microphone access is off. Allow it in iPhone Settings to speak a question."
        case .onDeviceUnavailable:
            "On-device transcription is not available for the current language on this iPhone. You can still type your question."
        }
    }
}
