import SwiftUI

// Standard macOS settings form: pick an engine, then only that engine's options.
struct SettingsView: View {
    @Environment(ConversionStore.self) private var conversionStore
    @State private var preview = VoicePreviewService()

    var body: some View {
        @Bindable var conversionStore = conversionStore

        Form {
            Section {
                Picker("Voice engine", selection: $conversionStore.selectedEngine) {
                    ForEach(VoiceEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent {
                    Label(
                        isSelectedEngineReady ? "Ready" : "Needs setup",
                        systemImage: isSelectedEngineReady ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(isSelectedEngineReady ? Color.secondary : Color.red)
                } label: {
                    Text(conversionStore.selectedEngine.blurb)
                        .foregroundStyle(.secondary)
                }
            }

            switch conversionStore.selectedEngine {
            case .system: systemOptions
            case .piper: piperOptions
            case .custom: commandOptions
            }

            Section {
                LabeledContent("Try it") {
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
        }
        .formStyle(.grouped)
        .preferredColorScheme(.light)
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
            Picker("Voice", selection: $conversionStore.selectedSystemVoiceIdentifier) {
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
            Picker("Voice", selection: Binding(
                get: { conversionStore.piperModelPath },
                set: { path in
                    if let voice = conversionStore.installedPiperVoices.first(where: { $0.id == path }) {
                        conversionStore.selectPiperVoice(voice)
                    }
                }
            )) {
                ForEach(conversionStore.installedPiperVoices) { voice in
                    Text(voice.name).tag(voice.id)
                }
            }
            .disabled(conversionStore.installedPiperVoices.isEmpty)

            TextField("Voices folder", text: $conversionStore.piperVoicesDirectory)
            TextField("Piper program", text: $conversionStore.piperExecutablePath)
        } footer: {
            Text("Any .onnx voice with its .onnx.json next to it appears in the list.")
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

            LabeledContent("Presets") {
                Menu("Choose…") {
                    ForEach(CommandPreset.all) { preset in
                        Button(preset.name) {
                            conversionStore.customCommand = preset.command
                            conversionStore.customOutputExtension = preset.fileExtension
                        }
                    }
                }
                .fixedSize()
            }
        } footer: {
            Text("Runs once per chapter. {text_file} is the chapter text and {output} is the audio file the command must write.")
                .foregroundStyle(.secondary)
        }
    }
}

private extension VoiceEngine {
    var blurb: String {
        switch self {
        case .piper: "Neural voice on this Mac. Offline and fast."
        case .custom: "Any model with a command line, such as edge-tts or Silero."
        case .system: "Built into macOS. Always works, plainest sound."
        }
    }
}

// Ready-made command lines for the engines worth reaching for on Russian text.
private struct CommandPreset: Identifiable {
    let id: String
    let name: String
    let command: String
    let fileExtension: String

    /// Models that run from the project's own tool folder; offered only when installed there.
    private static func local(_ model: String, venv: String, script: String, voices: [(id: String, name: String)]) -> [CommandPreset] {
        let root = ConversionStore.defaultProjectRoot
        let python = root.appendingPathComponent(".tools/\(venv)/bin/python").path
        let script = root.appendingPathComponent("script/\(script)").path
        guard FileManager.default.isExecutableFile(atPath: python), FileManager.default.fileExists(atPath: script) else {
            return []
        }
        return voices.map { voice in
            CommandPreset(
                id: "\(venv)-\(voice.id)",
                name: "\(model), \(voice.name) (offline)",
                command: "'\(python)' '\(script)' {text_file} {output} \(voice.id)",
                fileExtension: "wav"
            )
        }
    }

    static let all: [CommandPreset] =
        local("Silero v5", venv: "silero-venv", script: "silero_tts.py", voices: [("xenia", "Xenia"), ("eugene", "Eugene")])
        + local("Qwen3-TTS", venv: "mlx-venv", script: "qwen_tts.py", voices: [("serena", "Serena"), ("ryan", "Ryan")])
        + [
        CommandPreset(
            id: "edge-svetlana",
            name: "edge-tts, Svetlana (online)",
            command: "edge-tts --voice ru-RU-SvetlanaNeural --file {text_file} --write-media {output}",
            fileExtension: "mp3"
        ),
        CommandPreset(
            id: "edge-dmitry",
            name: "edge-tts, Dmitry (online)",
            command: "edge-tts --voice ru-RU-DmitryNeural --file {text_file} --write-media {output}",
            fileExtension: "mp3"
        )
    ]
}
