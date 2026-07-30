import AVFoundation
import Foundation

enum TTSError: LocalizedError {
    case unsupportedEngine(VoiceEngine)
    case couldNotStart
    case missingRussianVoice
    case missingPiperRuntime
    case synthesisFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedEngine(let engine):
            "\(engine.title) synthesis is not implemented yet."
        case .couldNotStart:
            "System speech synthesis could not start."
        case .missingRussianVoice:
            "No Russian system voice is installed. Install a ru-RU voice in macOS System Settings."
        case .missingPiperRuntime:
            "Piper runtime or voice model is not configured."
        case .synthesisFailed:
            "System speech synthesis did not finish successfully."
        }
    }
}

struct TTSConfiguration: Sendable, Equatable {
    var engine: VoiceEngine
    var systemVoiceIdentifier: String?
    var piperExecutablePath: String?
    var piperModelPath: String?
    var piperConfigPath: String?
}

@MainActor
protocol TTSService {
    func synthesize(chapterText: String, configuration: TTSConfiguration, to outputURL: URL) async throws -> URL
}

@MainActor
struct SystemTTSService: TTSService {
    func synthesize(chapterText: String, configuration: TTSConfiguration, to outputURL: URL) async throws -> URL {
        switch configuration.engine {
        case .system:
            return try await synthesizeWithSystemVoice(
                chapterText: chapterText,
                voiceIdentifier: configuration.systemVoiceIdentifier,
                to: outputURL
            )
        case .piper:
            return try await synthesizeWithPiper(
                chapterText: chapterText,
                configuration: configuration,
                to: outputURL
            )
        case .neuralLocal:
            throw TTSError.unsupportedEngine(configuration.engine)
        }
    }

    private func synthesizeWithSystemVoice(chapterText: String, voiceIdentifier: String?, to outputURL: URL) async throws -> URL {
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let coordinator = SpeechSynthesisCoordinator(outputURL: outputURL, voiceIdentifier: voiceIdentifier)
        return try await withTaskCancellationHandler {
            try await coordinator.synthesize(chapterText)
        } onCancel: {
            Task { @MainActor in
                coordinator.cancel()
            }
        }
    }

    private func synthesizeWithPiper(chapterText: String, configuration: TTSConfiguration, to outputURL: URL) async throws -> URL {
        guard
            let executablePath = configuration.piperExecutablePath,
            let modelPath = configuration.piperModelPath,
            let configPath = configuration.piperConfigPath,
            FileManager.default.isExecutableFile(atPath: executablePath),
            FileManager.default.fileExists(atPath: modelPath),
            FileManager.default.fileExists(atPath: configPath)
        else {
            throw TTSError.missingPiperRuntime
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = [
                "--model", modelPath,
                "--config", configPath,
                "--output_file", outputURL.path
            ]

            let inputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardError = errorPipe

            try process.run()
            inputPipe.fileHandleForWriting.write(Data(chapterText.utf8))
            try inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw TTSError.synthesisFailed
            }
            return outputURL
        }.value
    }
}

@MainActor
private final class SpeechSynthesisCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    private let outputURL: URL
    private let voiceIdentifier: String?
    private var synthesizer: AVSpeechSynthesizer?
    private var audioFile: AVAudioFile?
    private var continuation: CheckedContinuation<URL, Error>?
    private var hasFinished = false

    init(outputURL: URL, voiceIdentifier: String?) {
        self.outputURL = outputURL
        self.voiceIdentifier = voiceIdentifier
    }

    func synthesize(_ text: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = self
            self.synthesizer = synthesizer

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.voice(for: text, preferredIdentifier: voiceIdentifier)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.write(utterance) { [weak self] buffer in
                guard let self else { return }
                Task { @MainActor in
                    self.handle(buffer)
                }
            }
        }
    }

    private static func voice(for text: String, preferredIdentifier: String?) -> AVSpeechSynthesisVoice? {
        if let preferredIdentifier, !preferredIdentifier.isEmpty {
            return AVSpeechSynthesisVoice(identifier: preferredIdentifier)
        }

        if text.listrLooksRussian {
            return preferredVoice(languagePrefix: "ru-RU")
        }

        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice(language: language)
            ?? preferredVoice(languagePrefix: String(language.prefix(2)))
    }

    private static func preferredVoice(languagePrefix: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(languagePrefix.lowercased()) }

        return voices.first { $0.quality == .premium }
            ?? voices.first { $0.quality == .enhanced }
            ?? voices.first
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

private extension String {
    var listrLooksRussian: Bool {
        let cyrillicCount = unicodeScalars.filter { (0x0400...0x04FF).contains(Int($0.value)) }.count
        let latinCount = unicodeScalars.filter {
            (0x0041...0x005A).contains(Int($0.value)) || (0x0061...0x007A).contains(Int($0.value))
        }.count
        return cyrillicCount > 0 && cyrillicCount >= latinCount
    }
}
