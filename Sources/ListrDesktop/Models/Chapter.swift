import Foundation

struct Chapter: Identifiable, Hashable, Sendable {
    enum Status: String, Hashable, Sendable {
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

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
