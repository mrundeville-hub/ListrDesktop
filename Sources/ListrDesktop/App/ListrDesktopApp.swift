import SwiftUI

@main
struct ListrDesktopApp: App {
    @State private var libraryStore = LibraryStore()
    @State private var conversionStore = ConversionStore()
    @State private var playbackStore = PlaybackStore()

    var body: some Scene {
        WindowGroup("Listr", id: "main") {
            ContentView()
                .environment(libraryStore)
                .environment(conversionStore)
                .environment(playbackStore)
                .frame(minWidth: 1120, minHeight: 720)
        }
        Settings {
            SettingsView()
                .environment(conversionStore)
                .frame(width: 520)
        }
    }
}
