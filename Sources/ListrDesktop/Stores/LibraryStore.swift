import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    var books: [Book]
    var selectedBookID: Book.ID?
    var isImporting = false
    var isLoading = false
    var importError: String?
    var persistenceError: String?

    @ObservationIgnored private let persistence: LibraryPersistenceService?
    @ObservationIgnored private var hasLoadedPersistedLibrary = false

    init(books: [Book] = [], persistence: LibraryPersistenceService? = .applicationSupport) {
        self.books = books
        self.persistence = persistence
        self.selectedBookID = books.first?.id
    }

    var selectedBook: Book? {
        guard let selectedBookID else { return nil }
        return books.first { $0.id == selectedBookID }
    }

    func importPlaceholderBook() {
        let book = Book(
            id: UUID(),
            title: "New Imported Book",
            author: "Unknown author",
            chapterCount: 18,
            duration: 0,
            status: .imported,
            progress: 0,
            addedAt: .now
        )
        books.insert(book, at: 0)
        selectedBookID = book.id
        saveLibrary()
    }

    func loadPersistedLibraryIfNeeded() async {
        guard !hasLoadedPersistedLibrary, let persistence else { return }
        hasLoadedPersistedLibrary = true
        isLoading = true
        persistenceError = nil
        defer { isLoading = false }

        do {
            let persisted = try await Task.detached(priority: .userInitiated) {
                try persistence.load()
            }.value
            books = persisted.books
            selectedBookID = persisted.selectedBookID ?? persisted.books.first?.id
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func importBook(from url: URL) async {
        isImporting = true
        importError = nil
        defer { isImporting = false }

        do {
            let imported = try await Task.detached(priority: .userInitiated) {
                try BookImportService().importBook(from: url)
            }.value

            let book = Book(
                id: UUID(),
                title: imported.title,
                author: imported.author,
                chapterCount: imported.chapters.count,
                duration: 0,
                status: .imported,
                progress: 0,
                addedAt: .now,
                sourcePath: imported.sourceURL.path,
                chapters: imported.chapters
            )
            books.insert(book, at: 0)
            selectedBookID = book.id
            saveLibrary()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func saveLibrary() {
        guard let persistence else { return }
        let snapshot = PersistedLibrary(books: books, selectedBookID: selectedBookID)
        Task.detached(priority: .utility) {
            try? persistence.save(snapshot)
        }
    }

    @MainActor static let preview = LibraryStore(books: [
        Book(id: UUID(), title: "Master and Margarita", author: "Mikhail Bulgakov", chapterCount: 32, duration: 39_600, status: .ready, progress: 1, addedAt: .now.addingTimeInterval(-86_400)),
        Book(id: UUID(), title: "Roadside Picnic", author: "Arkady and Boris Strugatsky", chapterCount: 12, duration: 14_400, status: .converting, progress: 0.62, addedAt: .now.addingTimeInterval(-7_200)),
        Book(id: UUID(), title: "Notes from Underground", author: "Fyodor Dostoevsky", chapterCount: 9, duration: 0, status: .imported, progress: 0, addedAt: .now.addingTimeInterval(-1_200))
    ], persistence: nil)
}
