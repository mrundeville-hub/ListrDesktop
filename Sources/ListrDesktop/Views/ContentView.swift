import SwiftUI

// Two screens in one window: the library grid, and one open book. The player bar is shared.
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
        ZStack {
            ListrBackdrop()

            if let book = openBook {
                BookView(book: book, onBack: { openBookID = nil }, onRemove: { bookPendingRemoval = book })
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
            } else {
                LibraryView(
                    onOpen: open,
                    onImport: { isImporterPresented = true },
                    onRemove: { bookPendingRemoval = $0 }
                )
                .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: .top) // top bars sit level with the traffic lights
        .animation(.smooth(duration: 0.3), value: openBookIDString)
        .listrWindowStyle()
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { BookFormat.detect(from: $0) != nil }) else { return false }
            importBook(from: url)
            return true
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: BookFormat.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importBook(from: url)
            case .failure(let error):
                libraryStore.importError = error.localizedDescription
            }
        }
        // Saved here, not in the book screen, so the position survives leaving the book.
        .onChange(of: playbackStore.elapsed) { _, elapsed in
            guard let bookID = playbackStore.currentBookID, let chapterID = playbackStore.currentChapterID else {
                return
            }
            libraryStore.updatePlaybackPosition(bookID: bookID, chapterID: chapterID, position: elapsed)
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
        }
    }

    private func open(_ book: Book) {
        libraryStore.selectedBookID = book.id // convert / regenerate act on the selected book
        openBookID = book.id
    }

    // A freshly imported book opens straight away: the next step is always "convert it".
    private func importBook(from url: URL) {
        Task {
            await libraryStore.importBook(from: url)
            if libraryStore.importError == nil {
                openBookID = libraryStore.selectedBookID
            }
        }
    }
}
