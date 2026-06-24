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
    var resumePosition: TimeInterval? = nil

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
