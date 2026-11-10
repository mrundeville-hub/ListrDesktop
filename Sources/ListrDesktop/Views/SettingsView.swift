import SwiftUI

// Standard macOS settings form. One "Voice" menu lists every voice that is ready to use;
// the engine behind it and its options follow from that choice.
struct SettingsView: View {
    @Environment(ConversionStore.self) private var conversionStore
    @State private var preview = VoicePreviewService()

    var body: some View {
        Form {
            Section {
                Picker("Voice", selection: voiceChoice) {
                    Section("Piper — offline, fast") {
                        ForEach(conversionStore.installedPiperVoices) { voice in
                            Text(voice.name).tag(Choice.piper(voice.id))
                        }
                    }
                    ForEach(CommandPreset.groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.presets) { preset in
                                Text(preset.name).tag(Choice.preset(preset.id))
                            }
                        }
                    }
                    Section("Other") {
                        Text("macOS system voice").tag(Choice.system)
                        Text("Custom command…").tag(Choice.custom)
                    }
                }

                LabeledContent {
                    Label(
                        isSelectedEngineReady ? "Ready" : "Needs setup",
                        systemImage: isSelectedEngineReady ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(isSelectedEngineReady ? Color.secondary : Color.red)
                } label: {
                    Button(preview.isRunning ? "Preparing…" : "Play a sample sentence") {
                        Task { await preview.play(configuration: conversionStore.activeConfiguration) }
                    }
                    .disabled(preview.isRunning)
                }

                if let errorMessage = preview.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            } footer: {
                Text("A new voice applies to chapters converted from now on. To redo a finished book, open it and choose Regenerate Audio from the ⋯ menu.")
                    .foregroundStyle(.secondary)
            }

            switch conversionStore.selectedEngine {
            case .system: systemOptions
            case .piper: piperOptions
            case .custom: commandOptions
            }
        }
        .formStyle(.grouped)
        .preferredColorScheme(.light)
    }

    // MARK: Voice choice

    private enum Choice: Hashable {
        case piper(String)  // model path
        case preset(String) // preset id
        case system
        case custom
    }

    private var voiceChoice: Binding<Choice> {
        Binding {
            switch conversionStore.selectedEngine {
            case .piper:
                return .piper(conversionStore.piperModelPath)
            case .system:
                return .system
            case .custom:
                let preset = CommandPreset.all.first { $0.command == conversionStore.customCommand }
                return preset.map { .preset($0.id) } ?? .custom
            }
        } set: { choice in
            switch choice {
            case .piper(let path):
                if let voice = conversionStore.installedPiperVoices.first(where: { $0.id == path }) {
                    conversionStore.selectPiperVoice(voice)
                }
                conversionStore.selectedEngine = .piper
            case .preset(let id):
                guard let preset = CommandPreset.all.first(where: { $0.id == id }) else { return }
                conversionStore.customCommand = preset.command
                conversionStore.customOutputExtension = preset.fileExtension
                conversionStore.selectedEngine = .custom
            case .system:
                conversionStore.selectedEngine = .system
            case .custom:
                // Start from a blank command unless one is already being edited.
                if CommandPreset.all.contains(where: { $0.command == conversionStore.customCommand }) {
                    conversionStore.customCommand = ""
                }
                conversionStore.selectedEngine = .custom
            }
        }
    }

    private var isSelectedEngineReady: Bool {
        switch conversionStore.selectedEngine {
        case .system: true
        case .piper: conversionStore.isPiperReady
        case .custom: conversionStore.isCustomCommandReady
        }
    }

    // MARK: Options per engine

    private var systemOptions: some View {
        @Bindable var conversionStore = conversionStore

        return Section {
            Picker("System voice", selection: $conversionStore.selectedSystemVoiceIdentifier) {
                Text("Automatic").tag("")
                Section("Russian") {
                    ForEach(conversionStore.russianSystemVoices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
                Section("All installed") {
                    ForEach(conversionStore.installedSystemVoices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
            }
        } footer: {
            Text("Compact voices sound robotic. Better ones are free: System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.")
                .foregroundStyle(.secondary)
        }
    }

    private var piperOptions: some View {
        @Bindable var conversionStore = conversionStore

        return Section {
            TextField("Voices folder", text: $conversionStore.piperVoicesDirectory)
            TextField("Piper program", text: $conversionStore.piperExecutablePath)
        } footer: {
            Text("Any .onnx voice with its .onnx.json in the voices folder appears in the Voice menu.")
                .foregroundStyle(.secondary)
        }
    }

    private var commandOptions: some View {
        @Bindable var conversionStore = conversionStore

        return Section {
            TextField("Command", text: $conversionStore.customCommand, axis: .vertical)
                .lineLimit(1...4)
                .fontDesign(.monospaced)

            TextField("Audio format", text: $conversionStore.customOutputExtension, prompt: Text("wav"))
        } footer: {
            Text("Runs once per chapter. {text_file} is the chapter text and {output} is the audio file the command must write.")
                .foregroundStyle(.secondary)
        }
    }
}

// Ready-made command lines for the engines worth reaching for on Russian text.
private struct CommandPreset: Identifiable {
    let id: String
    let name: String
    let command: String
    let fileExtension: String

    struct Group {
        let title: String
        let presets: [CommandPreset]
    }

    /// Models that run from the project's own tool folder; offered only when installed there.
    private static func local(venv: String, script: String, voices: [(id: String, name: String)]) -> [CommandPreset] {
        let root = ConversionStore.defaultProjectRoot
        let python = root.appendingPathComponent(".tools/\(venv)/bin/python").path
        let script = root.appendingPathComponent("script/\(script)").path
        guard FileManager.default.isExecutableFile(atPath: python), FileManager.default.fileExists(atPath: script) else {
            return []
        }
        return voices.map { voice in
            CommandPreset(
                id: "\(venv)-\(voice.id)",
                name: voice.name,
                command: "'\(python)' '\(script)' {text_file} {output} \(voice.id)",
                fileExtension: "wav"
            )
        }
    }

    private static func edge(_ voice: String, _ name: String) -> CommandPreset {
        CommandPreset(
            id: "edge-\(voice)",
            name: name,
            command: "edge-tts --voice \(voice) --file {text_file} --write-media {output}",
            fileExtension: "mp3"
        )
    }

    static let groups: [Group] = [
        Group(
            title: "Silero v5 — offline, best Russian",
            presets: local(venv: "silero-venv", script: "silero_tts.py", voices: [
                ("xenia", "Xenia"), ("baya", "Baya"), ("kseniya", "Kseniya"), ("eugene", "Eugene"), ("aidar", "Aidar")
            ])
        ),
        Group(
            title: "Qwen3-TTS — offline, most natural, slow",
            presets: local(venv: "mlx-venv", script: "qwen_tts.py", voices: [
                ("serena", "Serena"), ("vivian", "Vivian"), ("ryan", "Ryan"), ("aiden", "Aiden")
            ])
        ),
        Group(
            title: "edge-tts — online",
            presets: [edge("ru-RU-SvetlanaNeural", "Svetlana"), edge("ru-RU-DmitryNeural", "Dmitry")]
        )
    ].filter { !$0.presets.isEmpty }

    static let all: [CommandPreset] = groups.flatMap(\.presets)
}
