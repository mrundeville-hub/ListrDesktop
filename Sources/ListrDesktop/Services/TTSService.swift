import AVFoundation
import Foundation
import os

enum TTSError: LocalizedError {
    case unsupportedEngine(VoiceEngine)
    case couldNotStart
    case missingRussianVoice
    case missingPiperRuntime
    case missingCommand
    case synthesisFailed
    case commandFailed(status: Int32, message: String)
    case emptyOutput

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
        case .missingCommand:
            "No synthesis command is configured. Add one in Settings → Command engine."
        case .synthesisFailed:
            "System speech synthesis did not finish successfully."
        case .commandFailed(let status, let message):
            message.isEmpty
                ? "The synthesis command exited with code \(status)."
                : "The synthesis command failed (code \(status)): \(message)"
        case .emptyOutput:
            "The synthesis command finished but produced no audio."
        }
    }
}

struct TTSConfiguration: Sendable, Equatable {
    var engine: VoiceEngine
    var systemVoiceIdentifier: String?
    var piperExecutablePath: String?
    var piperModelPath: String?
    var piperConfigPath: String?
    /// Shell command for the `.custom` engine. `{text_file}` and `{output}` are substituted.
    var customCommand: String = ""
    var customOutputExtension: String = "wav"

    /// Container format each engine writes, used to name the chapter file on disk.
    var outputFileExtension: String {
        switch engine {
        case .system: "aiff"
        case .piper: "wav"
        case .custom:
            // ".mp3" and " mp3" both mean mp3
            customOutputExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).isEmpty
                ? "wav"
                : customOutputExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }
    }
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
        case .custom:
            return try await synthesizeWithCommand(
                chapterText: chapterText,
                configuration: configuration,
                to: outputURL
            )
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

        let process = Process()
        let python = URL(fileURLWithPath: executablePath).deletingLastPathComponent().appendingPathComponent("python")
        return try await run(process, chapterText: chapterText, to: outputURL) { textURL in
            if FileManager.default.isExecutableFile(atPath: python.path) {
                // Sentence by sentence through Piper's Python API, so each sentence's exact
                // position in the audio is known and the word highlight stays in step.
                let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("listr-piper-runner.py")
                try Data(Self.piperRunnerScript.utf8).write(to: scriptURL, options: .atomic)
                process.executableURL = python
                process.arguments = [scriptURL.path, modelPath, configPath, textURL.path, outputURL.path]
                process.standardInput = FileHandle.nullDevice
            } else {
                // Bare piper binary: audio only, timings are estimated.
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = ["--model", modelPath, "--config", configPath, "--output_file", outputURL.path]
                process.standardInput = try FileHandle(forReadingFrom: textURL)
            }
        }
    }

    /// Runs a user-supplied shell command so any local or CLI-driven model can narrate a chapter.
    /// The chapter text is handed over as a file — it never goes through the command line.
    private func synthesizeWithCommand(chapterText: String, configuration: TTSConfiguration, to outputURL: URL) async throws -> URL {
        let template = configuration.customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { throw TTSError.missingCommand }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.environment = Self.environmentWithCommonToolPaths()
        return try await run(process, chapterText: chapterText, to: outputURL) { textURL in
            process.standardInput = FileHandle.nullDevice
            process.arguments = ["-c", template
                .replacingOccurrences(of: "{text_file}", with: Self.shellQuoted(textURL.path))
                .replacingOccurrences(of: "{output}", with: Self.shellQuoted(outputURL.path))]
        }
    }

    /// Writes the chapter to a temp file, runs the process off the main actor and checks it
    /// produced audio. Cancelling the task terminates the process instead of letting it finish.
    private func run(
        _ process: Process,
        chapterText: String,
        to outputURL: URL,
        configure: (URL) throws -> Void
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let textURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("listr-\(UUID().uuidString).txt")
        try Data(chapterText.utf8).write(to: textURL)
        defer { try? FileManager.default.removeItem(at: textURL) }
        try configure(textURL)

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        let (status, errorData) = try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try process.run()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, errorData)
            }.value
        } onCancel: {
            // ponytail: kills the direct child only; a command that forks its own children
            // (e.g. `a && b`) keeps the last one running until it exits by itself.
            if process.isRunning { process.terminate() }
        }

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }
        guard status == 0 else {
            throw TTSError.commandFailed(status: status, message: Self.tail(of: errorData))
        }
        try Self.verifyNonEmptyAudio(at: outputURL)
        return outputURL
    }

    /// Splits the chapter into sentences, synthesizes them one after another into one WAV and
    /// writes `<output>.segments.json` with where each sentence starts and ends.
    nonisolated private static let piperRunnerScript = #"""
    import json, re, sys, wave
    from piper import PiperVoice

    model, config, text_path, out_path = sys.argv[1:5]
    text = open(text_path, encoding="utf-8").read()
    voice = PiperVoice.load(model, config_path=config)

    # Split after punctuation that is followed by a space: at sentence ends once a piece has
    # 30+ characters (so "т. е." and initials stay attached), at commas and dashes once it has
    # 90+, so a long sentence still gives several exact anchors.
    spans, start = [], None
    for match in re.finditer(r'.+?(?:[.!?…,;:—–]+["»”)\]]*(?:\s+|$)|$)', text, re.S):
        if start is None:
            start = match.start()
        length = match.end() - start
        strong = re.search(r'[.!?…]["»”)\]]*\s*$', match.group()) is not None
        if length >= 90 or (strong and length >= 30):
            spans.append((start, match.end()))
            start = None
    if start is not None:
        spans.append((start, len(text)))

    def utf16(value):
        return len(value.encode("utf-16-le")) // 2

    segments, frames, rate, offset, previous = [], 0, None, 0, 0
    with wave.open(out_path, "wb") as wav:
        for a, b in spans:
            offset += utf16(text[previous:a])
            previous = a
            written = 0
            for chunk in voice.synthesize(text[a:b]):
                if rate is None:
                    rate = chunk.sample_rate
                    wav.setnchannels(chunk.sample_channels)
                    wav.setsampwidth(chunk.sample_width)
                    wav.setframerate(rate)
                data = chunk.audio_int16_bytes
                wav.writeframes(data)
                written += len(data) // (chunk.sample_width * chunk.sample_channels)
            if written:
                segments.append({
                    "location": offset, "length": utf16(text[a:b]),
                    "start": frames / rate, "end": (frames + written) / rate,
                })
                frames += written
        if rate is None:
            sys.exit("Piper produced no audio for this chapter.")

    with open(out_path + ".segments.json", "w") as handle:
        json.dump(segments, handle)
    """#

    // A GUI app inherits a bare PATH, so Homebrew and pipx tools would not be found otherwise.
    nonisolated private static func environmentWithCommonToolPaths() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let toolPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.local/bin",                          // pipx / uv
            "/Library/Frameworks/Python.framework/Versions/Current/bin", // python.org installs
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
        environment["PATH"] = environment["PATH"].map { "\($0):\(toolPaths)" } ?? toolPaths
        return environment
    }

    nonisolated private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func tail(of errorData: Data) -> String {
        let text = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.suffix(400))
    }

    nonisolated private static func verifyNonEmptyAudio(at url: URL) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        guard let size, size > 0 else { throw TTSError.emptyOutput }
    }
}

@MainActor
private final class SpeechSynthesisCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    private let outputURL: URL
    private let voiceIdentifier: String?
    private var synthesizer: AVSpeechSynthesizer?
    private var audioFile: AVAudioFile?
    // Filled straight from the synthesizer's thread, so every marker delivered before the
    // final buffer is already here when finish() runs.
    private let markers = OSAllocatedUnfairLock(initialState: [(location: Int, length: Int, byteOffset: Int)]())
    private var bytesPerSecond: Double = 0
    private var framesWritten: Double = 0
    private var sampleRate: Double = 0
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
            let markers = markers
            synthesizer.write(utterance, toBufferCallback: { [weak self] buffer in
                guard let self else { return }
                Task { @MainActor in
                    self.handle(buffer)
                }
            }, toMarkerCallback: { newMarkers in
                // The voice says exactly where each word starts in the audio it is writing.
                let words = newMarkers.filter { $0.mark == .word }.map {
                    (location: $0.textRange.location, length: $0.textRange.length, byteOffset: Int($0.byteSampleOffset))
                }
                markers.withLock { $0.append(contentsOf: words) }
            })
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
            sampleRate = pcmBuffer.format.sampleRate
            bytesPerSecond = sampleRate * Double(pcmBuffer.format.streamDescription.pointee.mBytesPerFrame)
            framesWritten += Double(pcmBuffer.frameLength)
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

    private func writeWordSegments() {
        let sorted = markers.withLock { $0 }.sorted { $0.byteOffset < $1.byteOffset }
        guard bytesPerSecond > 0, sampleRate > 0, !sorted.isEmpty else { return }
        let segments = sorted.enumerated().map { index, marker in
            TimingSegment(
                location: marker.location,
                length: marker.length,
                start: Double(marker.byteOffset) / bytesPerSecond,
                end: index + 1 < sorted.count
                    ? Double(sorted[index + 1].byteOffset) / bytesPerSecond
                    : framesWritten / sampleRate
            )
        }
        if let data = try? JSONEncoder().encode(segments) {
            try? data.write(to: TimingSegment.sidecarURL(for: outputURL))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !hasFinished else { return }
        hasFinished = true

        synthesizer?.delegate = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        audioFile = nil
        if case .success = result {
            writeWordSegments()
        }

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
