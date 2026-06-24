import AVFoundation
import Foundation

enum TTSError: LocalizedError {
    case unsupportedEngine(VoiceEngine)
    case couldNotStart
    case synthesisFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedEngine(let engine):
            "\(engine.title) synthesis is not implemented yet."
        case .couldNotStart:
            "System speech synthesis could not start."
        case .synthesisFailed:
            "System speech synthesis did not finish successfully."
        }
    }
}

@MainActor
protocol TTSService {
    func synthesize(chapterText: String, using engine: VoiceEngine, to outputURL: URL) async throws -> URL
}

@MainActor
struct SystemTTSService: TTSService {
    func synthesize(chapterText: String, using engine: VoiceEngine, to outputURL: URL) async throws -> URL {
        guard engine == .system else {
            throw TTSError.unsupportedEngine(engine)
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let coordinator = SpeechSynthesisCoordinator(outputURL: outputURL)
        return try await withTaskCancellationHandler {
            try await coordinator.synthesize(chapterText)
        } onCancel: {
            Task { @MainActor in
                coordinator.cancel()
            }
        }
    }
}

@MainActor
private final class SpeechSynthesisCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    private let outputURL: URL
    private var synthesizer: AVSpeechSynthesizer?
    private var audioFile: AVAudioFile?
    private var continuation: CheckedContinuation<URL, Error>?
    private var hasFinished = false

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func synthesize(_ text: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = self
            self.synthesizer = synthesizer

            let utterance = AVSpeechUtterance(string: text)
            synthesizer.write(utterance) { [weak self] buffer in
                guard let self else { return }
                Task { @MainActor in
                    self.handle(buffer)
                }
            }
        }
    }

    func cancel() {
        synthesizer?.stopSpeaking(at: .immediate)
        finish(.failure(CancellationError()))
    }

    private func handle(_ buffer: AVAudioBuffer) {
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
            finish(.failure(TTSError.synthesisFailed))
            return
        }

        guard pcmBuffer.frameLength > 0 else {
            finish(.success(outputURL))
            return
        }

        do {
            if audioFile == nil {
                audioFile = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
            }
            try audioFile?.write(from: pcmBuffer)
        } catch {
            finish(.failure(TTSError.synthesisFailed))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            finish(.success(outputURL))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            finish(.failure(TTSError.synthesisFailed))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !hasFinished else { return }
        hasFinished = true

        synthesizer?.delegate = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        audioFile = nil

        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
