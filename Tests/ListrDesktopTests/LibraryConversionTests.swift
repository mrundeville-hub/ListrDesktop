import Foundation
import Testing
@testable import ListrDesktop

@Suite("Library conversion")
@MainActor
struct LibraryConversionTests {
    @Test("converts pending chapters and resumes ready chapters")
    func convertsPendingChapters() async throws {
        let directory = try TemporaryDirectory()
        let readyURL = directory.url.appendingPathComponent("ready.aiff")
        try Data("ready".utf8).write(to: readyURL)

        let bookID = UUID()
        let store = LibraryStore(
            books: [
                Book(
                    id: bookID,
                    title: "Conversion Book",
                    author: "Test Author",
                    chapterCount: 2,
                    duration: 0,
                    status: .queued,
                    progress: 0.5,
                    addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    sourcePath: nil,
                    chapters: [
                        Chapter(id: UUID(), index: 1, title: "Ready", text: "Already done", status: .ready, audioPath: readyURL.path, timingPath: nil),
                        Chapter(id: UUID(), index: 2, title: "Pending", text: "Needs audio", status: .pending, audioPath: nil, timingPath: nil)
                    ]
                )
            ],
            persistence: nil,
            ttsService: FakeTTSService(),
            audioRootURL: directory.url.appendingPathComponent("Audio")
        )
        store.selectedBookID = bookID

        let task = try #require(store.convertSelectedBook(using: VoiceEngine.system))
        await task.value

        let converted = try #require(store.selectedBook)
        #expect(converted.status == Book.Status.ready)
        #expect(converted.progress == 1)
        #expect(converted.chapters.allSatisfy { $0.status == Chapter.Status.ready })
        #expect(converted.chapters[0].audioPath == readyURL.path)

        let generatedPath = try #require(converted.chapters[1].audioPath)
        #expect(FileManager.default.fileExists(atPath: generatedPath))
        #expect(String(data: try Data(contentsOf: URL(fileURLWithPath: generatedPath)), encoding: .utf8) == "Needs audio")
    }

    @Test("marks failed chapter without losing completed audio")
    func marksFailedChapter() async throws {
        let directory = try TemporaryDirectory()
        let readyURL = directory.url.appendingPathComponent("ready.aiff")
        try Data("ready".utf8).write(to: readyURL)

        let bookID = UUID()
        let readyChapterID = UUID()
        let failingChapterID = UUID()
        let store = LibraryStore(
            books: [
                Book(
                    id: bookID,
                    title: "Failing Book",
                    author: "Test Author",
                    chapterCount: 2,
                    duration: 0,
                    status: .queued,
                    progress: 0.5,
                    addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    sourcePath: nil,
                    chapters: [
                        Chapter(id: readyChapterID, index: 1, title: "Ready", text: "Already done", status: .ready, audioPath: readyURL.path, timingPath: nil),
                        Chapter(id: failingChapterID, index: 2, title: "Broken", text: "fail", status: .pending, audioPath: nil, timingPath: nil)
                    ]
                )
            ],
            persistence: nil,
            ttsService: FailingTTSService(),
            audioRootURL: directory.url.appendingPathComponent("Audio")
        )
        store.selectedBookID = bookID

        let task = try #require(store.convertSelectedBook(using: VoiceEngine.system))
        await task.value

        let converted = try #require(store.selectedBook)
        #expect(converted.status == Book.Status.failed)
        #expect(converted.progress == 0.5)
        #expect(converted.chapters[0].id == readyChapterID)
        #expect(converted.chapters[0].status == Chapter.Status.ready)
        #expect(converted.chapters[1].id == failingChapterID)
        #expect(converted.chapters[1].status == Chapter.Status.failed)
        #expect(store.conversionError == "Synthetic TTS failure")
    }

    @Test("cancels converting chapter and keeps book retryable")
    func cancelsConvertingChapter() async throws {
        let directory = try TemporaryDirectory()
        let bookID = UUID()
        let service = SlowTTSService()
        let store = LibraryStore(
            books: [
                Book(
                    id: bookID,
                    title: "Cancelable Book",
                    author: "Test Author",
                    chapterCount: 1,
                    duration: 0,
                    status: .imported,
                    progress: 0,
                    addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    sourcePath: nil,
                    chapters: [
                        Chapter(id: UUID(), index: 1, title: "Pending", text: "Long text", status: .pending, audioPath: nil, timingPath: nil)
                    ]
                )
            ],
            persistence: nil,
            ttsService: service,
            audioRootURL: directory.url.appendingPathComponent("Audio")
        )
        store.selectedBookID = bookID

        let task = try #require(store.convertSelectedBook(using: VoiceEngine.system))
        await service.waitUntilStarted()
        store.cancelConversion()
        await task.value

        let converted = try #require(store.selectedBook)
        #expect(converted.status == Book.Status.imported)
        #expect(converted.progress == 0)
        #expect(converted.chapters[0].status == Chapter.Status.pending)
        #expect(store.conversionError == nil)
    }

    @Test("stores playback resume position on matching chapter")
    func storesPlaybackPosition() throws {
        let bookID = UUID()
        let chapterID = UUID()
        let store = LibraryStore(
            books: [
                Book(
                    id: bookID,
                    title: "Playback Book",
                    author: "Test Author",
                    chapterCount: 1,
                    duration: 0,
                    status: .ready,
                    progress: 1,
                    addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    sourcePath: nil,
                    chapters: [
                        Chapter(id: chapterID, index: 1, title: "Ready", text: "Text", status: .ready, audioPath: "/tmp/audio.aiff", timingPath: nil)
                    ]
                )
            ],
            persistence: nil,
            ttsService: FakeTTSService()
        )

        store.updatePlaybackPosition(bookID: bookID, chapterID: chapterID, position: 42.5)

        #expect(store.books[0].chapters[0].resumePosition == 42.5)
    }
}

@MainActor
private struct FakeTTSService: TTSService {
    func synthesize(chapterText: String, using engine: VoiceEngine, to outputURL: URL) async throws -> URL {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(chapterText.utf8).write(to: outputURL)
        return outputURL
    }
}

@MainActor
private struct FailingTTSService: TTSService {
    func synthesize(chapterText: String, using engine: VoiceEngine, to outputURL: URL) async throws -> URL {
        throw FakeTTSError()
    }
}

private struct FakeTTSError: LocalizedError {
    var errorDescription: String? { "Synthetic TTS failure" }
}

@MainActor
private final class SlowTTSService: TTSService {
    private var hasStarted = false
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func synthesize(chapterText: String, using engine: VoiceEngine, to outputURL: URL) async throws -> URL {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil

        do {
            try await Task.sleep(for: .seconds(60))
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(chapterText.utf8).write(to: outputURL)
            return outputURL
        } catch is CancellationError {
            throw CancellationError()
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
