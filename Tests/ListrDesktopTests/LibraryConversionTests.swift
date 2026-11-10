import Foundation
import Testing
@testable import ListrDesktop

private extension TTSConfiguration {
    static let testSystem = TTSConfiguration(
        engine: .system,
        systemVoiceIdentifier: "ru-test",
        piperExecutablePath: nil,
        piperModelPath: nil,
        piperConfigPath: nil
    )
}

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

        let task = try #require(store.convertSelectedBook(configuration: .testSystem))
        await task.value

        let converted = try #require(store.selectedBook)
        #expect(converted.status == Book.Status.ready)
        #expect(converted.progress == 1)
        #expect(converted.chapters.allSatisfy { $0.status == Chapter.Status.ready })
        #expect(converted.chapters[0].audioPath == readyURL.path)

        let generatedPath = try #require(converted.chapters[1].audioPath)
        #expect(FileManager.default.fileExists(atPath: generatedPath))
        #expect(String(data: try Data(contentsOf: URL(fileURLWithPath: generatedPath)), encoding: .utf8) == "Needs audio")

        let timingPath = try #require(converted.chapters[1].timingPath)
        #expect(FileManager.default.fileExists(atPath: timingPath))
        let timing = try JSONDecoder().decode(ChapterTiming.self, from: Data(contentsOf: URL(fileURLWithPath: timingPath)))
        #expect(timing.words.map(\.text) == ["Needs", "audio"])
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

        let task = try #require(store.convertSelectedBook(configuration: .testSystem))
        await task.value

        let converted = try #require(store.selectedBook)
        #expect(converted.status == Book.Status.failed)
        #expect(converted.progress == 0.5)
        #expect(converted.chapters[0].id == readyChapterID)
        #expect(converted.chapters[0].status == Chapter.Status.ready)
        #expect(converted.chapters[1].id == failingChapterID)
        #expect(converted.chapters[1].status == Chapter.Status.failed)
        #expect(converted.chapters[1].lastError == "Synthetic TTS failure")
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

        let task = try #require(store.convertSelectedBook(configuration: .testSystem))
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

    @Test("regenerates existing audio with fresh timing")
    func regeneratesExistingAudio() async throws {
        let directory = try TemporaryDirectory()
        let oldAudioURL = directory.url.appendingPathComponent("old.aiff")
        let oldTimingURL = directory.url.appendingPathComponent("old.timing.json")
        try Data("old".utf8).write(to: oldAudioURL)
        try Data("old timing".utf8).write(to: oldTimingURL)

        let bookID = UUID()
        let store = LibraryStore(
            books: [
                Book(
                    id: bookID,
                    title: "Regenerate Book",
                    author: "Test Author",
                    chapterCount: 1,
                    duration: 1,
                    status: .ready,
                    progress: 1,
                    addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    sourcePath: nil,
                    chapters: [
                        Chapter(id: UUID(), index: 1, title: "Ready", text: "Fresh audio", status: .ready, audioPath: oldAudioURL.path, timingPath: oldTimingURL.path)
                    ]
                )
            ],
            persistence: nil,
            ttsService: FakeTTSService(),
            audioRootURL: directory.url.appendingPathComponent("Audio")
        )
        store.selectedBookID = bookID

        let task = try #require(store.regenerateSelectedBook(configuration: .testSystem))
        await task.value

        let converted = try #require(store.selectedBook)
        #expect(converted.status == .ready)
        #expect(!FileManager.default.fileExists(atPath: oldAudioURL.path))
        #expect(!FileManager.default.fileExists(atPath: oldTimingURL.path))
        #expect(converted.chapters[0].audioPath != oldAudioURL.path)
        #expect(converted.chapters[0].timingPath != oldTimingURL.path)
    }

    @Test("removes a book with its generated audio but keeps the imported source file")
    func removesBookAndGeneratedAudio() throws {
        let directory = try TemporaryDirectory()
        let audioRootURL = directory.url.appendingPathComponent("Audio")
        let sourceURL = directory.url.appendingPathComponent("book.txt")
        try Data("source".utf8).write(to: sourceURL)

        let bookID = UUID()
        let bookAudioURL = audioRootURL.appendingPathComponent(bookID.uuidString)
        try FileManager.default.createDirectory(at: bookAudioURL, withIntermediateDirectories: true)
        let audioURL = bookAudioURL.appendingPathComponent("001-Ready.aiff")
        let timingURL = bookAudioURL.appendingPathComponent("001-Ready.timing.json")
        try Data("audio".utf8).write(to: audioURL)
        try Data("{}".utf8).write(to: timingURL)

        let otherBookID = UUID()
        let store = LibraryStore(
            books: [
                Book(
                    id: bookID,
                    title: "Removable Book",
                    author: "Test Author",
                    chapterCount: 1,
                    duration: 1,
                    status: .ready,
                    progress: 1,
                    addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    sourcePath: sourceURL.path,
                    chapters: [
                        Chapter(id: UUID(), index: 1, title: "Ready", text: "Done", status: .ready, audioPath: audioURL.path, timingPath: timingURL.path)
                    ]
                ),
                Book(
                    id: otherBookID,
                    title: "Kept Book",
                    author: "Test Author",
                    chapterCount: 0,
                    duration: 0,
                    status: .imported,
                    progress: 0,
                    addedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ],
            persistence: nil,
            ttsService: FakeTTSService(),
            audioRootURL: audioRootURL
        )
        store.selectedBookID = bookID

        store.removeBook(id: bookID)

        #expect(store.books.map(\.id) == [otherBookID])
        #expect(store.selectedBookID == otherBookID)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(!FileManager.default.fileExists(atPath: timingURL.path))
        #expect(!FileManager.default.fileExists(atPath: bookAudioURL.path))
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test("command engine substitutes placeholders and keeps the chapter text intact")
    func commandEngineSubstitutesPlaceholders() async throws {
        let directory = try TemporaryDirectory()
        let outputURL = directory.url.appendingPathComponent("chapter.wav")
        let configuration = TTSConfiguration(
            engine: .custom,
            systemVoiceIdentifier: nil,
            piperExecutablePath: nil,
            piperModelPath: nil,
            piperConfigPath: nil,
            customCommand: "cp {text_file} {output}",
            customOutputExtension: "wav"
        )

        #expect(configuration.outputFileExtension == "wav")

        let producedURL = try await SystemTTSService().synthesize(
            chapterText: "Утро было ясное, и город просыпался медленно.",
            configuration: configuration,
            to: outputURL
        )

        let written = try String(contentsOf: producedURL, encoding: .utf8)
        #expect(written == "Утро было ясное, и город просыпался медленно.")
    }

    @Test("command engine reports a failing command instead of leaving a silent chapter")
    func commandEngineReportsFailure() async throws {
        let directory = try TemporaryDirectory()
        let outputURL = directory.url.appendingPathComponent("chapter.wav")
        let configuration = TTSConfiguration(
            engine: .custom,
            systemVoiceIdentifier: nil,
            piperExecutablePath: nil,
            piperModelPath: nil,
            piperConfigPath: nil,
            customCommand: "echo 'voice model missing' >&2; exit 3 # {text_file} {output}",
            customOutputExtension: "wav"
        )

        await #expect(throws: TTSError.self) {
            try await SystemTTSService().synthesize(
                chapterText: "Текст главы",
                configuration: configuration,
                to: outputURL
            )
        }
    }

    @Test("command engine rejects a command that writes nothing")
    func commandEngineRejectsEmptyOutput() async throws {
        let directory = try TemporaryDirectory()
        let outputURL = directory.url.appendingPathComponent("chapter.wav")
        let configuration = TTSConfiguration(
            engine: .custom,
            systemVoiceIdentifier: nil,
            piperExecutablePath: nil,
            piperModelPath: nil,
            piperConfigPath: nil,
            customCommand: "true # {text_file} {output}",
            customOutputExtension: "wav"
        )

        await #expect(throws: TTSError.self) {
            try await SystemTTSService().synthesize(
                chapterText: "Текст главы",
                configuration: configuration,
                to: outputURL
            )
        }
    }

    @Test("synthesizes Russian audio with local Piper when installed")
    func synthesizesRussianWithPiperWhenInstalled() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let executableURL = root.appendingPathComponent(".tools/piper-venv/bin/piper")
        let modelURL = root.appendingPathComponent(".tools/piper-voices/ru_RU-irina-medium/ru_RU-irina-medium.onnx")
        let configURL = root.appendingPathComponent(".tools/piper-voices/ru_RU-irina-medium/ru_RU-irina-medium.onnx.json")

        guard
            FileManager.default.isExecutableFile(atPath: executableURL.path),
            FileManager.default.fileExists(atPath: modelURL.path),
            FileManager.default.fileExists(atPath: configURL.path)
        else {
            return
        }

        let directory = try TemporaryDirectory()
        let outputURL = directory.url.appendingPathComponent("piper.wav")
        let service = SystemTTSService()
        let synthesizedURL = try await service.synthesize(
            chapterText: "Привет. Это проверка русского синтеза.",
            configuration: TTSConfiguration(
                engine: .piper,
                systemVoiceIdentifier: nil,
                piperExecutablePath: executableURL.path,
                piperModelPath: modelURL.path,
                piperConfigPath: configURL.path
            ),
            to: outputURL
        )

        #expect(FileManager.default.fileExists(atPath: synthesizedURL.path))
        #expect((try FileManager.default.attributesOfItem(atPath: synthesizedURL.path)[.size] as? Int ?? 0) > 10_000)

        // The runner reports where the text sits in the audio, which keeps the highlight in step.
        let segments = TimingSegment.takeSidecar(for: synthesizedURL)
        #expect(segments.first?.location == 0)
        #expect((segments.last?.end ?? 0) > 1)
    }

    @Test("system voice reports where each word starts")
    func systemVoiceWritesWordSegments() async throws {
        // Needs a real macOS speech voice; hosted CI runners have no audio stack to rely on.
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }

        let directory = try TemporaryDirectory()
        let outputURL = directory.url.appendingPathComponent("system.aiff")
        let synthesizedURL = try await SystemTTSService().synthesize(
            chapterText: "One two three four.",
            configuration: .testSystem,
            to: outputURL
        )

        let segments = TimingSegment.takeSidecar(for: synthesizedURL)
        #expect(segments.count == 4)
        #expect(segments.map(\.start) == segments.map(\.start).sorted())
    }
}

@MainActor
private struct FakeTTSService: TTSService {
    func synthesize(chapterText: String, configuration: TTSConfiguration, to outputURL: URL) async throws -> URL {
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
    func synthesize(chapterText: String, configuration: TTSConfiguration, to outputURL: URL) async throws -> URL {
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

    func synthesize(chapterText: String, configuration: TTSConfiguration, to outputURL: URL) async throws -> URL {
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
