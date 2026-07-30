import AVFoundation
import Foundation
import Observation

@Observable
final class ConversionStore {
    var selectedEngine: VoiceEngine {
        didSet { defaults.set(selectedEngine.rawValue, forKey: Keys.selectedEngine) }
    }

    var selectedSystemVoiceIdentifier: String {
        didSet { defaults.set(selectedSystemVoiceIdentifier, forKey: Keys.selectedSystemVoiceIdentifier) }
    }

    var piperExecutablePath: String {
        didSet { defaults.set(piperExecutablePath, forKey: Keys.piperExecutablePath) }
    }

    var piperModelPath: String {
        didSet { defaults.set(piperModelPath, forKey: Keys.piperModelPath) }
    }

    var piperConfigPath: String {
        didSet { defaults.set(piperConfigPath, forKey: Keys.piperConfigPath) }
    }

    var speed: Double {
        didSet { defaults.set(speed, forKey: Keys.speed) }
    }

    var maxParallelJobs: Int {
        didSet { defaults.set(maxParallelJobs, forKey: Keys.maxParallelJobs) }
    }

    var preserveBattery: Bool {
        didSet { defaults.set(preserveBattery, forKey: Keys.preserveBattery) }
    }

    var generateWordTimings: Bool {
        didSet { defaults.set(generateWordTimings, forKey: Keys.generateWordTimings) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedEngine = VoiceEngine(rawValue: defaults.string(forKey: Keys.selectedEngine) ?? "") ?? .system
        selectedSystemVoiceIdentifier = defaults.string(forKey: Keys.selectedSystemVoiceIdentifier) ?? ""
        piperExecutablePath = defaults.string(forKey: Keys.piperExecutablePath) ?? Self.defaultPiperExecutablePath
        piperModelPath = defaults.string(forKey: Keys.piperModelPath) ?? Self.defaultPiperModelPath
        piperConfigPath = defaults.string(forKey: Keys.piperConfigPath) ?? Self.defaultPiperConfigPath
        speed = defaults.object(forKey: Keys.speed) as? Double ?? 1.0
        maxParallelJobs = defaults.object(forKey: Keys.maxParallelJobs) as? Int ?? 1
        preserveBattery = defaults.object(forKey: Keys.preserveBattery) as? Bool ?? true
        generateWordTimings = defaults.object(forKey: Keys.generateWordTimings) as? Bool ?? true

        if !availableEngines.contains(selectedEngine) {
            selectedEngine = .system
        }
    }

    var estimatedLoad: String {
        if preserveBattery || maxParallelJobs == 1 {
            return "Light background load"
        }
        return "Faster conversion, higher CPU use"
    }

    var installedSystemVoices: [SystemVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { lhs, rhs in
                if lhs.language == rhs.language { return lhs.name < rhs.name }
                return lhs.language < rhs.language
            }
            .map(SystemVoiceOption.init)
    }

    var russianSystemVoices: [SystemVoiceOption] {
        installedSystemVoices.filter { $0.language.lowercased().hasPrefix("ru") }
    }

    var selectedVoiceTitle: String {
        guard !selectedSystemVoiceIdentifier.isEmpty else {
            return russianSystemVoices.first?.displayName ?? "Auto"
        }
        return installedSystemVoices.first { $0.id == selectedSystemVoiceIdentifier }?.displayName ?? "Missing voice"
    }

    var isPiperReady: Bool {
        FileManager.default.isExecutableFile(atPath: piperExecutablePath)
            && FileManager.default.fileExists(atPath: piperModelPath)
            && FileManager.default.fileExists(atPath: piperConfigPath)
    }

    var availableEngines: [VoiceEngine] {
        isPiperReady ? [.piper, .system] : [.system]
    }

    var activeConfiguration: TTSConfiguration {
        TTSConfiguration(
            engine: selectedEngine,
            systemVoiceIdentifier: selectedSystemVoiceIdentifier.isEmpty ? nil : selectedSystemVoiceIdentifier,
            piperExecutablePath: piperExecutablePath.isEmpty ? nil : piperExecutablePath,
            piperModelPath: piperModelPath.isEmpty ? nil : piperModelPath,
            piperConfigPath: piperConfigPath.isEmpty ? nil : piperConfigPath
        )
    }

    private static var defaultPiperExecutablePath: String {
        defaultProjectRoot
            .appendingPathComponent(".tools/piper-venv/bin/piper")
            .path
    }

    private static var defaultPiperModelPath: String {
        defaultProjectRoot
            .appendingPathComponent(".tools/piper-voices/ru_RU-irina-medium/ru_RU-irina-medium.onnx")
            .path
    }

    private static var defaultPiperConfigPath: String {
        defaultProjectRoot
            .appendingPathComponent(".tools/piper-voices/ru_RU-irina-medium/ru_RU-irina-medium.onnx.json")
            .path
    }

    private static var defaultProjectRoot: URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            let candidate = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

struct SystemVoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let quality: String

    init(_ voice: AVSpeechSynthesisVoice) {
        id = voice.identifier
        name = voice.name
        language = voice.language
        quality = switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Compact"
        }
    }

    var displayName: String {
        "\(name) · \(language) · \(quality)"
    }
}

private enum Keys {
    static let selectedEngine = "conversion.selectedEngine"
    static let selectedSystemVoiceIdentifier = "conversion.selectedSystemVoiceIdentifier"
    static let piperExecutablePath = "conversion.piperExecutablePath"
    static let piperModelPath = "conversion.piperModelPath"
    static let piperConfigPath = "conversion.piperConfigPath"
    static let speed = "conversion.speed"
    static let maxParallelJobs = "conversion.maxParallelJobs"
    static let preserveBattery = "conversion.preserveBattery"
    static let generateWordTimings = "conversion.generateWordTimings"
}
