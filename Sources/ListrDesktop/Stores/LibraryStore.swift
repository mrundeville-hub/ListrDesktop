import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    var books: [Book]
    var selectedBookID: Book.ID?
    var isImporting = false
    var importError: String?

    init(books: [Book] = []) {
        self.books = books
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
        } catch {
            importError = error.localizedDescription
        }
    }

    @MainActor static let preview = LibraryStore(books: [
        Book(id: UUID(), title: "Master and Margarita", author: "Mikhail Bulgakov", chapterCount: 32, duration: 39_600, status: .ready, progress: 1, addedAt: .now.addingTimeInterval(-86_400)),
        Book(id: UUID(), title: "Roadside Picnic", author: "Arkady and Boris Strugatsky", chapterCount: 12, duration: 14_400, status: .converting, progress: 0.62, addedAt: .now.addingTimeInterval(-7_200)),
        Book(id: UUID(), title: "Notes from Underground", author: "Fyodor Dostoevsky", chapterCount: 9, duration: 0, status: .imported, progress: 0, addedAt: .now.addingTimeInterval(-1_200))
    ])
}
