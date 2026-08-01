import SwiftUI

struct SettingsView: View {
    @Environment(ConversionStore.self) private var conversionStore
    @State private var preview = VoicePreviewService()

    var body: some View {
        @Bindable var conversionStore = conversionStore

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Narration")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ListrTheme.ink)
                    Spacer()

                    Button(preview.isRunning ? "Synthesizing…" : "Preview voice") {
                        Task { await preview.play(configuration: conversionStore.activeConfiguration) }
                    }
                    .buttonStyle(ListrPillButtonStyle())
                    .disabled(preview.isRunning)
                    .help("Speak one sample sentence with the current engine")
                    .fixedSize()
                }
                .padding(.horizontal, 4)

                if let errorMessage = preview.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }

                SettingsCard(title: "Voice", icon: "person.wave.2.fill") {
                    SettingsRow("Engine") {
                        Picker("Engine", selection: $conversionStore.selectedEngine) {
                            ForEach(conversionStore.availableEngines) { engine in
                                Text(engine.title).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    SettingsRow("System voice") {
                        Menu {
                            Button("Auto Russian") { conversionStore.selectedSystemVoiceIdentifier = "" }
                            Section("Russian") {
                                ForEach(conversionStore.russianSystemVoices) { voice in
                                    Button(voice.displayName) {
                                        conversionStore.selectedSystemVoiceIdentifier = voice.id
                                    }
                                }
                            }
                            Section("All installed") {
                                ForEach(conversionStore.installedSystemVoices) { voice in
                                    Button(voice.displayName) {
                                        conversionStore.selectedSystemVoiceIdentifier = voice.id
                                    }
                                }
                            }
                        } label: {
                            ListrChip(text: conversionStore.selectedVoiceTitle, icon: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .disabled(conversionStore.selectedEngine != .system)
                    }
                }

                SettingsCard(title: "Conversion load", icon: "gauge.with.needle") {
                    SettingsToggle("Battery-friendly", isOn: $conversionStore.preserveBattery)
                    SettingsToggle("Word timing files", isOn: $conversionStore.generateWordTimings)

                    SettingsRow("Parallel jobs") {
                        Stepper(
                            "\(conversionStore.maxParallelJobs)",
                            value: $conversionStore.maxParallelJobs,
                            in: 1...3
                        )
                        .monospacedDigit()
                    }

                    ListrChip(text: conversionStore.estimatedLoad, icon: "bolt.fill")
                }

                SettingsCard(title: "Piper voices", icon: "shippingbox.fill") {
                    SettingsRow("Voice") {
                        if conversionStore.installedPiperVoices.isEmpty {
                            Text("No .onnx voices found in the voices folder")
                                .font(.system(size: 12))
                                .foregroundStyle(ListrTheme.mutedLabel)
                        } else {
                            Menu {
                                ForEach(conversionStore.installedPiperVoices) { voice in
                                    Button(voice.name) { conversionStore.selectPiperVoice(voice) }
                                }
                            } label: {
                                ListrChip(text: conversionStore.selectedPiperVoiceName, icon: "chevron.down")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }

                    PathField(title: "Voices folder", text: $conversionStore.piperVoicesDirectory)
                    PathField(title: "Executable", text: $conversionStore.piperExecutablePath)

                    ListrChip(
                        text: conversionStore.isPiperReady ? "Piper is ready" : "Piper is not configured",
                        icon: conversionStore.isPiperReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        fill: conversionStore.isPiperReady ? ListrTheme.accentWash : Color.red.opacity(0.1),
                        tint: conversionStore.isPiperReady ? ListrTheme.accent : .red
                    )
                }

                SettingsCard(title: "Command engine", icon: "terminal.fill") {
                    Text("Runs any local or CLI model. `{text_file}` is the chapter text, `{output}` is the audio file to write. See docs/VOICES.md for ready-made recipes.")
                        .font(.system(size: 12))
                        .foregroundStyle(ListrTheme.mutedLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    PathField(title: "Command", text: $conversionStore.customCommand)

                    SettingsRow("Presets") {
                        HStack(spacing: 8) {
                            ForEach(CommandPreset.all) { preset in
                                Button(preset.name) {
                                    conversionStore.customCommand = preset.command
                                    conversionStore.customOutputExtension = preset.fileExtension
                                }
                                .buttonStyle(ListrPillButtonStyle(prominent: false))
                                .help(preset.detail)
                                .fixedSize()
                            }
                        }
                    }

                    SettingsRow("Output format") {
                        TextField("wav", text: $conversionStore.customOutputExtension)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: ListrTheme.mono))
                            .frame(width: 80)
                    }

                    ListrChip(
                        text: conversionStore.isCustomCommandReady ? "Command engine is ready" : "Add a command containing {output}",
                        icon: conversionStore.isCustomCommandReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        fill: conversionStore.isCustomCommandReady ? ListrTheme.accentWash : ListrTheme.chip,
                        tint: conversionStore.isCustomCommandReady ? ListrTheme.accent : ListrTheme.mutedLabel
                    )
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(ListrTheme.paper)
        .tint(ListrTheme.ink)
        .toggleStyle(.switch)
    }
}

// Ready-made command lines for the engines worth reaching for on Russian text.
private struct CommandPreset: Identifiable {
    let id: String
    let name: String
    let detail: String
    let command: String
    let fileExtension: String

    static let all: [CommandPreset] = [
        CommandPreset(
            id: "edge-svetlana",
            name: "edge-tts · Svetlana",
            detail: "Microsoft neural Russian voice, female. Best quality, needs a network connection.",
            command: "edge-tts --voice ru-RU-SvetlanaNeural --file {text_file} --write-media {output}",
            fileExtension: "mp3"
        ),
        CommandPreset(
            id: "edge-dmitry",
            name: "edge-tts · Dmitry",
            detail: "Microsoft neural Russian voice, male. Best quality, needs a network connection.",
            command: "edge-tts --voice ru-RU-DmitryNeural --file {text_file} --write-media {output}",
            fileExtension: "mp3"
        )
    ]
}

// Fixed label column so every control in the window lines up.
private struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(ListrTheme.mutedLabel)
                .frame(width: 108, alignment: .leading)
            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ListrTheme.accent)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ListrTheme.ink)
                Spacer()
            }

            content
                .font(.system(size: 13))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listrCard(radius: 18)
    }
}

private struct PathField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ListrTheme.mutedLabel)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: ListrTheme.mono))
                .labelsHidden()
        }
    }
}
