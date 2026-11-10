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

    /// Folder scanned for Piper voices. Stored (not derived) so editing it refreshes the voice menu.
    var piperVoicesDirectory: String {
        didSet { defaults.set(piperVoicesDirectory, forKey: Keys.piperVoicesDirectory) }
    }

    var customCommand: String {
        didSet { defaults.set(customCommand, forKey: Keys.customCommand) }
    }

    var customOutputExtension: String {
        didSet { defaults.set(customOutputExtension, forKey: Keys.customOutputExtension) }
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
        piperVoicesDirectory = defaults.string(forKey: Keys.piperVoicesDirectory)
            ?? Self.defaultPiperVoicesDirectory
        customCommand = defaults.string(forKey: Keys.customCommand) ?? ""
        customOutputExtension = defaults.string(forKey: Keys.customOutputExtension) ?? "wav"

        if !availableEngines.contains(selectedEngine) {
            selectedEngine = .system
        }
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

    var isCustomCommandReady: Bool {
        customCommand.contains("{output}")
    }

    var availableEngines: [VoiceEngine] {
        var engines: [VoiceEngine] = []
        if isPiperReady { engines.append(.piper) }
        if isCustomCommandReady { engines.append(.custom) }
        engines.append(.system)
        return engines
    }

    /// Every Piper voice sitting next to the selected one, so switching voices is a menu pick
    /// instead of editing two file paths by hand.
    var installedPiperVoices: [PiperVoiceOption] {
        let root = URL(fileURLWithPath: piperVoicesDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return entries
            .flatMap { entry -> [URL] in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory)
                guard isDirectory.boolValue else { return [entry] }
                return (try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
            }
            .filter { $0.pathExtension == "onnx" }
            .compactMap { modelURL in
                let configURL = modelURL.appendingPathExtension("json")
                guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
                return PiperVoiceOption(
                    id: modelURL.path,
                    name: modelURL.deletingPathExtension().lastPathComponent,
                    configPath: configURL.path
                )
            }
            .sorted { $0.name < $1.name }
    }

    var selectedPiperVoiceName: String {
        guard !piperModelPath.isEmpty else { return "No voice selected" }
        return URL(fileURLWithPath: piperModelPath).deletingPathExtension().lastPathComponent
    }

    func selectPiperVoice(_ voice: PiperVoiceOption) {
        piperModelPath = voice.id
        piperConfigPath = voice.configPath
    }

    var activeConfiguration: TTSConfiguration {
        TTSConfiguration(
            engine: selectedEngine,
            systemVoiceIdentifier: selectedSystemVoiceIdentifier.isEmpty ? nil : selectedSystemVoiceIdentifier,
            piperExecutablePath: piperExecutablePath.isEmpty ? nil : piperExecutablePath,
            piperModelPath: piperModelPath.isEmpty ? nil : piperModelPath,
            piperConfigPath: piperConfigPath.isEmpty ? nil : piperConfigPath,
            customCommand: customCommand,
            customOutputExtension: customOutputExtension
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

    private static var defaultPiperVoicesDirectory: String {
        defaultProjectRoot.appendingPathComponent(".tools/piper-voices").path
    }

    static var defaultProjectRoot: URL {
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

struct PiperVoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let configPath: String
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
    static let customCommand = "conversion.customCommand"
    static let customOutputExtension = "conversion.customOutputExtension"
    static let piperVoicesDirectory = "conversion.piperVoicesDirectory"
}
