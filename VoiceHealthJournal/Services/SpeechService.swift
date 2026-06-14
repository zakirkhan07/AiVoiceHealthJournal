import Foundation
import AVFoundation
import Speech

/// Records audio and transcribes it live using SFSpeechRecognizer.
/// Handles every permission/failure state explicitly — the UI binds to `state`.
@MainActor
final class SpeechService: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case requestingPermission
        case denied(String)          // human-readable reason + how to fix
        case recording
        case unavailable(String)     // recognizer offline / not supported
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var audioLevel: Float = 0   // 0...1 for waveform UI

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        state = .requestingPermission

        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            state = .denied("Speech recognition permission is required. Enable it in Settings → Privacy → Speech Recognition.")
            return false
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            state = .denied("Microphone access is required. Enable it in Settings → Privacy → Microphone.")
            return false
        }

        state = .idle
        return true
    }

    // MARK: - Recording

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Speech recognition is temporarily unavailable. You can type your check-in instead.")
            return
        }

        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device for privacy — health speech should not leave the phone for transcription.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.updateLevel(from: buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil {
                    // Don't blow away what we have — partial transcript is still saved.
                    self.stop()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        state = .recording
        AnalyticsLogger.shared.log(.recordingStarted)
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioLevel = 0
        if state == .recording { state = .idle }
        AnalyticsLogger.shared.log(.recordingStopped, props: ["chars": "\(transcript.count)"])
    }

    private nonisolated func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(max(frames, 1)))
        let level = min(max(rms * 12, 0), 1)
        Task { @MainActor [weak self] in self?.audioLevel = level }
    }
}
