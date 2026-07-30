import Foundation

struct Chapter: Identifiable, Hashable, Sendable, Codable {
    enum Status: String, Hashable, Sendable, Codable {
        case pending = "Pending"
        case converting = "Converting"
        case ready = "Ready"
        case failed = "Failed"
    }

    let id: UUID
    var index: Int
    var title: String
    var text: String
    var status: Status
    var audioPath: String?
    var timingPath: String?
    var lastError: String? = nil
    var resumePosition: TimeInterval? = nil

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Ready to play: marked ready *and* the generated file still exists on disk.
    var isReady: Bool {
        guard status == .ready, let audioPath else { return false }
        return FileManager.default.fileExists(atPath: audioPath)
    }
}
