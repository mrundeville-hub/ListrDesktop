import Foundation

struct PersistedLibrary: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var books: [Book]
    var selectedBookID: Book.ID?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        books: [Book],
        selectedBookID: Book.ID?
    ) {
        self.schemaVersion = schemaVersion
        self.books = books
        self.selectedBookID = selectedBookID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case books
        case selectedBookID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        books = try container.decode([Book].self, forKey: .books)
        selectedBookID = try container.decodeIfPresent(Book.ID.self, forKey: .selectedBookID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(books, forKey: .books)
        try container.encodeIfPresent(selectedBookID, forKey: .selectedBookID)
    }
}

struct LibraryPersistenceService: Sendable {
    struct UnsupportedSchemaError: LocalizedError {
        let foundVersion: Int

        var errorDescription: String? {
            "This library was saved by a newer version of ListrDesktop (schema \(foundVersion)). Update the app to open it."
        }
    }

    let fileURL: URL

    static var applicationSupport: LibraryPersistenceService {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LibraryPersistenceService(fileURL: baseURL.appending(path: "ListrDesktop/library.json"))
    }

    func load() throws -> PersistedLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PersistedLibrary(books: [], selectedBookID: nil)
        }

        let data = try Data(contentsOf: fileURL)
        let persisted = try JSONDecoder.listr.decode(PersistedLibrary.self, from: data)
        if persisted.schemaVersion > PersistedLibrary.currentSchemaVersion {
            throw UnsupportedSchemaError(foundVersion: persisted.schemaVersion)
        }
        // ponytail: current schema is 1; add step-up migrations here when version 2 exists
        return persisted
    }

    func save(_ library: PersistedLibrary) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder.listr.encode(library)
        let temporaryURL = directory.appending(path: ".library.json.tmp")
        try data.write(to: temporaryURL, options: .atomic)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
    }
}

private extension JSONEncoder {
    static var listr: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var listr: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
