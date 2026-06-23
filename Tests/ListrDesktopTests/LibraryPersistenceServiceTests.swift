import Foundation
import Testing
@testable import ListrDesktop

@Suite("Library persistence")
struct LibraryPersistenceServiceTests {
    @Test("saves and loads library JSON")
    func savesAndLoadsLibrary() throws {
        let directory = try TemporaryDirectory()
        let service = LibraryPersistenceService(fileURL: directory.url.appending(path: "library.json"))
        let selectedID = UUID()
        let book = Book(
            id: selectedID,
            title: "Saved Book",
            author: "Saved Author",
            chapterCount: 1,
            duration: 0,
            status: .imported,
            progress: 0,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourcePath: "/tmp/saved.fb2",
            chapters: [
                Chapter(id: UUID(), index: 1, title: "One", text: "Chapter text", status: .pending, audioPath: nil, timingPath: nil)
            ]
        )

        try service.save(PersistedLibrary(books: [book], selectedBookID: selectedID))
        let loaded = try service.load()

        #expect(loaded.selectedBookID == selectedID)
        #expect(loaded.books.count == 1)
        #expect(loaded.books[0].title == "Saved Book")
        #expect(loaded.books[0].chapters[0].text == "Chapter text")
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
