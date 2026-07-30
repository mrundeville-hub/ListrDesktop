import SwiftUI

struct SettingsView: View {
    @Environment(ConversionStore.self) private var conversionStore

    var body: some View {
        @Bindable var conversionStore = conversionStore

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Narration")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ListrTheme.ink)
                    Spacer()
                    ListrChip(
                        text: "listr",
                        icon: "waveform",
                        fill: ListrTheme.accentWash,
                        tint: ListrTheme.accent
                    )
                }
                .padding(.horizontal, 4)

                SettingsCard(title: "Voice", icon: "person.wave.2.fill") {
                    LabeledContent("Engine") {
                        Picker("Engine", selection: $conversionStore.selectedEngine) {
                            ForEach(conversionStore.availableEngines) { engine in
                                Text(engine.title).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    LabeledContent("System voice") {
                        Picker("System voice", selection: $conversionStore.selectedSystemVoiceIdentifier) {
                            Text("Auto Russian").tag("")
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
                        .labelsHidden()
                        .disabled(conversionStore.selectedEngine != .system)
                    }

                    ListrChip(text: conversionStore.selectedVoiceTitle, icon: "checkmark.seal.fill")
                }

                SettingsCard(title: "Conversion load", icon: "gauge.with.needle") {
                    Toggle("Prefer battery-friendly conversion", isOn: $conversionStore.preserveBattery)
                    Toggle("Generate word timing files", isOn: $conversionStore.generateWordTimings)
                    Stepper(
                        "Maximum parallel jobs: \(conversionStore.maxParallelJobs)",
                        value: $conversionStore.maxParallelJobs,
                        in: 1...3
                    )

                    ListrChip(text: conversionStore.estimatedLoad, icon: "bolt.fill")
                }

                SettingsCard(title: "Piper voice model", icon: "shippingbox.fill") {
                    PathField(title: "Executable", text: $conversionStore.piperExecutablePath)
                    PathField(title: "Model", text: $conversionStore.piperModelPath)
                    PathField(title: "Config", text: $conversionStore.piperConfigPath)

                    ListrChip(
                        text: conversionStore.isPiperReady ? "Piper is ready" : "Piper is not configured",
                        icon: conversionStore.isPiperReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        fill: conversionStore.isPiperReady ? ListrTheme.accentWash : Color.red.opacity(0.1),
                        tint: conversionStore.isPiperReady ? ListrTheme.accent : .red
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
