import SwiftUI

@main
struct ListrDesktopApp: App {
    @State private var libraryStore = LibraryStore()
    @State private var conversionStore = ConversionStore()
    @State private var playbackStore = PlaybackStore()
    @State private var overlayStore = OverlayStore()
    @State private var overlayWindowController = OverlayWindowController()

    var body: some Scene {
        WindowGroup("Listr", id: "main") {
            ContentView()
                .preferredColorScheme(.light) // cloud palette is light-only
                .environment(libraryStore)
                .environment(conversionStore)
                .environment(playbackStore)
                .environment(overlayStore)
                .frame(minWidth: 1120, minHeight: 720)
                .onAppear {
                    playbackStore.onChapterFinished = { bookID, chapterID in
                        autoAdvance(bookID: bookID, finishedChapterID: chapterID)
                    }
                    if overlayStore.isPresented {
                        presentOverlay()
                    }
                }
                .onChange(of: overlayStore.isPresented) { _, isPresented in
                    if isPresented {
                        presentOverlay()
                    } else {
                        overlayWindowController.dismiss()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 880)
        .defaultPosition(.center)
        Settings {
            SettingsView()
                .environment(conversionStore)
                .frame(width: 520, height: 640)
        }
        .commands {
            CommandMenu("Reading Overlay") {
                Button(overlayStore.isPresented ? "Hide Overlay" : "Show Overlay") {
                    overlayStore.toggle()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }

    private func presentOverlay() {
        overlayWindowController.present(
            overlayStore: overlayStore,
            playbackStore: playbackStore,
            libraryStore: libraryStore,
            conversionStore: conversionStore
        )
    }

    private func autoAdvance(bookID: Book.ID, finishedChapterID: Chapter.ID) {
        guard let book = libraryStore.books.first(where: { $0.id == bookID }) else { return }

        // Finished chapter restarts from the top next time.
        libraryStore.updatePlaybackPosition(bookID: bookID, chapterID: finishedChapterID, position: 0)

        guard let next = book.chapter(after: finishedChapterID) else { return }
        playbackStore.play(bookID: bookID, chapter: next, speed: conversionStore.speed)
    }
}
