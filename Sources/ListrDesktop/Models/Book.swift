import Foundation

struct Book: Identifiable, Hashable, Sendable, Codable {
    enum Status: String, Hashable, Sendable, Codable {
        case imported = "Imported"
        case queued = "Queued"
        case converting = "Converting"
        case ready = "Ready"
        case failed = "Needs attention"
    }

    let id: UUID
    var title: String
    var author: String
    var chapterCount: Int
    var duration: TimeInterval
    var status: Status
    var progress: Double
    var addedAt: Date
    var sourcePath: String? = nil
    var chapters: [Chapter] = []

    var durationLabel: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
