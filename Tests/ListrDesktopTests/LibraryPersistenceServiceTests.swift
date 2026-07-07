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
        #expect(loaded.schemaVersion == PersistedLibrary.currentSchemaVersion)
        #expect(loaded.books.count == 1)
        #expect(loaded.books[0].title == "Saved Book")
        #expect(loaded.books[0].chapters[0].text == "Chapter text")
    }

    @Test("rejects library JSON with a future schema version")
    func rejectsFutureSchemaVersion() throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appending(path: "library.json")
        try #"{"schemaVersion": 2, "books": []}"#.write(to: fileURL, atomically: true, encoding: .utf8)
        let service = LibraryPersistenceService(fileURL: fileURL)

        #expect(throws: LibraryPersistenceService.UnsupportedSchemaError.self) {
            try service.load()
        }
    }

    @MainActor
    @Test("loads legacy library JSON and repairs missing generated files")
    func loadsLegacyLibraryAndRepairsMissingAudio() async throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appending(path: "library.json")
        let selectedID = UUID()
        let chapterID = UUID()
        let missingAudioPath = directory.url.appending(path: "missing.aiff").path
        let legacyJSON = """
        {
          "books": [
            {
              "id": "\(selectedID.uuidString)",
              "title": "Legacy Book",
              "author": "Legacy Author",
              "chapterCount": 99,
              "duration": 120,
              "status": "Ready",
              "progress": 1,
              "addedAt": "2023-11-14T22:13:20Z",
              "sourcePath": null,
              "chapters": [
                {
                  "id": "\(chapterID.uuidString)",
                  "index": 1,
                  "title": "One",
                  "text": "Chapter text",
                  "status": "Ready",
                  "audioPath": "\(missingAudioPath)",
                  "timingPath": "\(directory.url.appending(path: "missing.timing.json").path)",
                  "resumePosition": 42
                }
              ]
            }
          ],
          "selectedBookID": "\(selectedID.uuidString)"
        }
        """
        try legacyJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = LibraryStore(
            persistence: LibraryPersistenceService(fileURL: fileURL),
            ttsService: FakeTTSServiceForPersistence()
        )

        await store.loadPersistedLibraryIfNeeded()

        let repaired = try #require(store.selectedBook)
        #expect(repaired.id == selectedID)
        #expect(repaired.chapterCount == 1)
        #expect(repaired.status == .imported)
        #expect(repaired.progress == 0)
        #expect(repaired.duration == 0)
        #expect(repaired.chapters[0].status == .pending)
        #expect(repaired.chapters[0].audioPath == nil)
        #expect(repaired.chapters[0].timingPath == nil)
        #expect(repaired.chapters[0].resumePosition == nil)
        #expect(repaired.chapters[0].lastError == "Generated audio file is missing. Convert this chapter again.")
    }
}

@MainActor
private struct FakeTTSServiceForPersistence: TTSService {
    func synthesize(chapterText: String, configuration: TTSConfiguration, to outputURL: URL) async throws -> URL {
        outputURL
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
