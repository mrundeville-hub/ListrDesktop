import SwiftUI

// One window, Mac-style: the sidebar (library and the books in progress), the library or one
// open book in the detail column, and the player floating over the bottom of it.
struct ContentView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore
    @State private var isImporterPresented = false
    // Remembered across launches: the app reopens on the book you were listening to.
    @AppStorage("library.openBookID") private var openBookIDString = ""
    @State private var bookPendingRemoval: Book?

    private var openBookID: Book.ID? {
        get { UUID(uuidString: openBookIDString) }
        nonmutating set { openBookIDString = newValue?.uuidString ?? "" }
    }

    private var openBook: Book? {
        libraryStore.books.first { $0.id == openBookID }
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(selection: sidebarSelection, onRemove: { bookPendingRemoval = $0 })
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 320)
        } detail: {
            Group {
                if let book = openBook {
                    BookView(book: book, onBack: { openBookID = nil }, onRemove: { bookPendingRemoval = book })
                } else {
                    LibraryView(
                        onOpen: open,
                        onImport: { isImporterPresented = true },
                        onRemove: { bookPendingRemoval = $0 }
                    )
                    .listrPlayerBar(playerBook) { if let playerBook { open(playerBook) } }
                    .animation(.smooth(duration: 0.3), value: playerBook?.id)
                }
            }
            .animation(.smooth(duration: 0.25), value: openBookIDString)
        }
        .background(PlaybackPositionSaver())
        .dropDestination(for: URL.self) { urls, _ in
            let books = urls.filter { BookFormat.detect(from: $0) != nil }
            guard !books.isEmpty else { return false }
            importBooks(from: books)
            return true
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: BookFormat.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importBooks(from: urls)
            case .failure(let error):
                libraryStore.importError = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Remove “\(bookPendingRemoval?.title ?? "")” from the library?",
            isPresented: Binding(
                get: { bookPendingRemoval != nil },
                set: { if !$0 { bookPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let book = bookPendingRemoval else { return }
                if playbackStore.currentBookID == book.id {
                    playbackStore.unload()
                }
                libraryStore.removeBook(id: book.id)
                bookPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { bookPendingRemoval = nil }
        } message: {
            Text("Its audio is deleted. The original book file stays where it is.")
        }
        .alert("Import failed", isPresented: Binding(
            get: { libraryStore.importError != nil },
            set: { if !$0 { libraryStore.importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(libraryStore.importError ?? "Unknown import error")
        }
        .alert("Conversion failed", isPresented: Binding(
            get: { libraryStore.conversionError != nil },
            set: { if !$0 { libraryStore.conversionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(libraryStore.conversionError ?? "Unknown conversion error")
        }
        .alert("Playback failed", isPresented: Binding(
            get: { playbackStore.playbackError != nil },
            set: { if !$0 { playbackStore.playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackStore.playbackError ?? "Unknown playback error")
        }
        .alert("Library storage failed", isPresented: Binding(
            get: { libraryStore.persistenceError != nil },
            set: { if !$0 { libraryStore.persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(libraryStore.persistenceError ?? "Unknown storage error")
        }
        .task {
            await libraryStore.loadPersistedLibraryIfNeeded()
            if ProcessInfo.processInfo.environment["LISTR_DEBUG_AUTOPLAY"] != nil, let book = libraryStore.books.first(where: { $0.title.contains("Minima") }), let chapter = book.resumeChapter {
                openBookID = book.id
                playbackStore.play(bookID: book.id, chapter: chapter, speed: 1)
                try? await Task.sleep(for: .seconds(4))
                playbackStore.togglePlayPause()
                if ProcessInfo.processInfo.environment["LISTR_DEBUG_AUTOPLAY"] == "seek" {
                }
            }
        }
        // Convert / regenerate act on the selected book: keep it the one on screen, also after a relaunch.
        .onChange(of: openBook?.id, initial: true) { _, id in
            if let id { libraryStore.selectedBookID = id }
        }
    }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { openBookID.map(SidebarItem.book) ?? .library },
            set: { item in
                if case .book(let id)? = item {
                    libraryStore.selectedBookID = id
                    openBookID = id
                } else {
                    openBookID = nil
                }
            }
        )
    }

    /// The book in the player bar on the library screen: what is loaded, else the one
    /// listened to last, so carrying on is one click away.
    private var playerBook: Book? {
        libraryStore.books.first { $0.id == playbackStore.currentBookID }
            ?? libraryStore.startedBooks.first { $0.resumeChapter != nil }
    }

    private func open(_ book: Book) {
        libraryStore.selectedBookID = book.id // convert / regenerate act on the selected book
        openBookID = book.id
    }

    // One freshly imported book opens straight away: the next step is always "convert it".
    // Several land in the library and leave the screen as it is.
    private func importBooks(from urls: [URL]) {
        Task {
            var failures: [String] = []
            for url in urls {
                await libraryStore.importBook(from: url)
                if let error = libraryStore.importError {
                    failures.append("\(url.lastPathComponent): \(error)")
                }
                // Importing selects the new book; in a batch, hand the selection straight back
                // to the book on screen so Convert never aims at a different one mid-import.
                if urls.count > 1, let openBookID {
                    libraryStore.selectedBookID = openBookID
                }
            }
            if urls.count == 1, failures.isEmpty {
                openBookID = libraryStore.selectedBookID
            }
            if !failures.isEmpty {
                libraryStore.importError = failures.joined(separator: "\n")
            }
        }
    }
}

// Saves the listening position as it moves. A view of its own so the 10 Hz playback clock
// re-renders only this, not the whole window. Lives above the book screen so the position
// is kept after leaving the book.
private struct PlaybackPositionSaver: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore

    var body: some View {
        Color.clear
            .onChange(of: playbackStore.elapsed) { save() }
            .onChange(of: playbackStore.isPlaying) { save(force: true) } // paused: keep the exact spot
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                save(force: true)
                libraryStore.saveNow()
            }
    }

    private func save(force: Bool = false) {
        guard let bookID = playbackStore.currentBookID, let chapterID = playbackStore.currentChapterID else { return }
        libraryStore.updatePlaybackPosition(bookID: bookID, chapterID: chapterID, position: playbackStore.elapsed, force: force)
    }
}
