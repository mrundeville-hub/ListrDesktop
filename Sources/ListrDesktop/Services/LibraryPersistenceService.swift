import Foundation

struct PersistedLibrary: Codable, Sendable {
    var books: [Book]
    var selectedBookID: Book.ID?
}

struct LibraryPersistenceService: Sendable {
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
        return try JSONDecoder.listr.decode(PersistedLibrary.self, from: data)
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
