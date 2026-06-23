import SwiftUI

struct SettingsView: View {
    @Environment(ConversionStore.self) private var conversionStore

    var body: some View {
        @Bindable var conversionStore = conversionStore

        Form {
            Picker("Default engine", selection: $conversionStore.selectedEngine) {
                ForEach(VoiceEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }

            Toggle("Prefer battery-friendly conversion", isOn: $conversionStore.preserveBattery)
            Stepper("Maximum parallel jobs: \(conversionStore.maxParallelJobs)", value: $conversionStore.maxParallelJobs, in: 1...3)
            Toggle("Generate word timing files", isOn: $conversionStore.generateWordTimings)
        }
        .formStyle(.grouped)
        .padding()
    }
}
