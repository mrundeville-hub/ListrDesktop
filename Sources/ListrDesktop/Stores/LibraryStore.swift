import AVFoundation
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
    var conversionError: String?

    @ObservationIgnored private let persistence: LibraryPersistenceService?
    @ObservationIgnored private let ttsService: any TTSService
    @ObservationIgnored private let audioRootURL: URL
    @ObservationIgnored private var hasLoadedPersistedLibrary = false
    @ObservationIgnored private var conversionTask: Task<Void, Never>?
    @ObservationIgnored private var convertingBookID: Book.ID?

    init(
        books: [Book] = [],
        persistence: LibraryPersistenceService? = .applicationSupport,
        ttsService: any TTSService = SystemTTSService(),
        audioRootURL: URL? = nil
    ) {
        self.books = books
        self.persistence = persistence
        self.ttsService = ttsService
        self.audioRootURL = audioRootURL ?? Self.defaultAudioRootURL()
        self.selectedBookID = books.first?.id
    }

    var selectedBook: Book? {
        guard let selectedBookID else { return nil }
        return books.first { $0.id == selectedBookID }
    }

    var isConverting: Bool {
        conversionTask != nil
    }

    var canConvertSelectedBook: Bool {
        guard !isConverting, let selectedBook else { return false }
        return selectedBook.chapters.contains { !isChapterReady($0) }
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

    @discardableResult
    func convertSelectedBook(using engine: VoiceEngine) -> Task<Void, Never>? {
        guard conversionTask == nil, let selectedBookID else { return nil }
        conversionError = nil
        convertingBookID = selectedBookID
        conversionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.conversionTask = nil
                self.convertingBookID = nil
            }
            await self.convertBook(id: selectedBookID, using: engine)
        }
        return conversionTask
    }

    func cancelConversion() {
        let bookID = convertingBookID
        conversionTask?.cancel()
        conversionTask = nil
        convertingBookID = nil

        guard let bookID, let bookIndex = books.firstIndex(where: { $0.id == bookID }) else {
            return
        }

        markConversionCancelled(forBookAt: bookIndex)
    }

    func updatePlaybackPosition(bookID: Book.ID, chapterID: Chapter.ID, position: TimeInterval) {
        guard
            let bookIndex = books.firstIndex(where: { $0.id == bookID }),
            let chapterIndex = books[bookIndex].chapters.firstIndex(where: { $0.id == chapterID })
        else {
            return
        }

        books[bookIndex].chapters[chapterIndex].resumePosition = max(position, 0)
        saveLibrary()
    }

    private func convertBook(id bookID: Book.ID, using engine: VoiceEngine) async {
        guard let initialBookIndex = books.firstIndex(where: { $0.id == bookID }) else { return }

        books[initialBookIndex].status = .queued
        updateBookProgress(at: initialBookIndex)
        saveLibrary()

        while
            let bookIndex = books.firstIndex(where: { $0.id == bookID }),
            let chapterIndex = nextConvertibleChapterIndex(forBookAt: bookIndex)
        {
            if Task.isCancelled {
                markConversionCancelled(forBookAt: bookIndex)
                return
            }

            books[bookIndex].status = .converting
            books[bookIndex].chapters[chapterIndex].status = .converting
            updateBookProgress(at: bookIndex)
            saveLibrary()

            let chapter = books[bookIndex].chapters[chapterIndex]
            var temporaryURL: URL?

            do {
                let finalURL = try chapterAudioURL(bookID: bookID, chapter: chapter)
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    books[bookIndex].chapters[chapterIndex].audioPath = finalURL.path
                    books[bookIndex].chapters[chapterIndex].status = .ready
                    updateBookStatus(at: bookIndex)
                    updateBookDuration(at: bookIndex)
                    saveLibrary()
                    continue
                }

                temporaryURL = finalURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(".\(finalURL.lastPathComponent).tmp.aiff")
                let synthesizedURL = try await ttsService.synthesize(
                    chapterText: chapter.text,
                    using: engine,
                    to: temporaryURL!
                )

                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: synthesizedURL)
                    markConversionCancelled(forBookAt: bookIndex)
                    return
                }

                try moveAtomically(from: synthesizedURL, to: finalURL)
                books[bookIndex].chapters[chapterIndex].audioPath = finalURL.path
                books[bookIndex].chapters[chapterIndex].status = .ready
                updateBookStatus(at: bookIndex)
                updateBookDuration(at: bookIndex)
                saveLibrary()
            } catch is CancellationError {
                if let temporaryURL {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }
                markConversionCancelled(forBookAt: bookIndex)
                return
            } catch {
                books[bookIndex].chapters[chapterIndex].status = .failed
                books[bookIndex].status = .failed
                conversionError = error.localizedDescription
                updateBookProgress(at: bookIndex)
                saveLibrary()
                return
            }
        }

        if let finalBookIndex = books.firstIndex(where: { $0.id == bookID }) {
            updateBookStatus(at: finalBookIndex)
            updateBookDuration(at: finalBookIndex)
            saveLibrary()
        }
    }

    private func nextConvertibleChapterIndex(forBookAt bookIndex: Int) -> Int? {
        books[bookIndex].chapters.firstIndex { chapter in
            !isChapterReady(chapter)
        }
    }

    private func updateBookStatus(at bookIndex: Int) {
        updateBookProgress(at: bookIndex)
        let chapters = books[bookIndex].chapters

        if chapters.isEmpty {
            books[bookIndex].status = .imported
        } else if chapters.allSatisfy({ isChapterReady($0) }) {
            books[bookIndex].status = .ready
        } else if chapters.contains(where: { $0.status == .failed }) {
            books[bookIndex].status = .failed
        } else if chapters.contains(where: { $0.status == .converting }) {
            books[bookIndex].status = .converting
        } else if chapters.contains(where: { $0.status == .ready }) {
            books[bookIndex].status = .queued
        } else {
            books[bookIndex].status = .imported
        }
    }

    private func updateBookProgress(at bookIndex: Int) {
        let chapters = books[bookIndex].chapters
        guard !chapters.isEmpty else {
            books[bookIndex].progress = 0
            return
        }

        let readyCount = chapters.filter { isChapterReady($0) }.count
        books[bookIndex].progress = Double(readyCount) / Double(chapters.count)
    }

    private func updateBookDuration(at bookIndex: Int) {
        books[bookIndex].duration = books[bookIndex].chapters.reduce(0) { total, chapter in
            guard isChapterReady(chapter), let audioPath = chapter.audioPath else { return total }
            return total + audioDuration(at: URL(fileURLWithPath: audioPath))
        }
    }

    private func markConversionCancelled(forBookAt bookIndex: Int) {
        for chapterIndex in books[bookIndex].chapters.indices where books[bookIndex].chapters[chapterIndex].status == .converting {
            books[bookIndex].chapters[chapterIndex].status = .pending
        }
        updateBookStatus(at: bookIndex)
        updateBookDuration(at: bookIndex)
        saveLibrary()
    }

    private func isChapterReady(_ chapter: Chapter) -> Bool {
        guard chapter.status == .ready, let audioPath = chapter.audioPath else {
            return false
        }
        return FileManager.default.fileExists(atPath: audioPath)
    }

    private func chapterAudioURL(bookID: Book.ID, chapter: Chapter) throws -> URL {
        let baseURL = audioRootURL.appendingPathComponent(bookID.uuidString)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let filename = String(format: "%03d-%@.aiff", chapter.index, safeFileName(chapter.title))
        return baseURL.appendingPathComponent(filename)
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "chapter" : String(name.prefix(80))
    }

    private func moveAtomically(from sourceURL: URL, to destinationURL: URL) throws {
        let directory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let replacementURL = directory.appendingPathComponent(".\(destinationURL.lastPathComponent).ready")
        try? FileManager.default.removeItem(at: replacementURL)
        try FileManager.default.moveItem(at: sourceURL, to: replacementURL)
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: replacementURL, to: destinationURL)
    }

    private func audioDuration(at url: URL) -> TimeInterval {
        guard let audioFile = try? AVAudioFile(forReading: url), audioFile.processingFormat.sampleRate > 0 else {
            return 0
        }
        return TimeInterval(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    private static func defaultAudioRootURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListrDesktop")
            .appendingPathComponent("Audio")
    }

    private func saveLibrary() {
        guard let persistence else { return }
        let snapshot = PersistedLibrary(books: books, selectedBookID: selectedBookID)
        Task.detached(priority: .utility) {
            try? persistence.save(snapshot)
        }
    }

    @MainActor static let preview = LibraryStore(
        books: [
            Book(id: UUID(), title: "Master and Margarita", author: "Mikhail Bulgakov", chapterCount: 32, duration: 39_600, status: .ready, progress: 1, addedAt: .now.addingTimeInterval(-86_400)),
            Book(id: UUID(), title: "Roadside Picnic", author: "Arkady and Boris Strugatsky", chapterCount: 12, duration: 14_400, status: .converting, progress: 0.62, addedAt: .now.addingTimeInterval(-7_200)),
            Book(id: UUID(), title: "Notes from Underground", author: "Fyodor Dostoevsky", chapterCount: 9, duration: 0, status: .imported, progress: 0, addedAt: .now.addingTimeInterval(-1_200))
        ],
        persistence: nil
    )
}
