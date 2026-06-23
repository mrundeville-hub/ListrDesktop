import SwiftUI

@main
struct ListrDesktopApp: App {
    @State private var libraryStore = LibraryStore.preview
    @State private var conversionStore = ConversionStore()

    var body: some Scene {
        WindowGroup("Listr", id: "main") {
            ContentView()
                .environment(libraryStore)
                .environment(conversionStore)
                .frame(minWidth: 1120, minHeight: 720)
        }
        Settings {
            SettingsView()
                .environment(conversionStore)
                .frame(width: 520)
        }
    }
}
