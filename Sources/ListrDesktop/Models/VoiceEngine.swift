import Foundation

enum VoiceEngine: String, CaseIterable, Identifiable, Sendable, Codable {
    case system
    case custom
    case piper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .custom: "Command"
        case .piper: "Piper"
        }
    }

    var loadProfile: String {
        switch self {
        case .system: "Lowest load"
        case .custom: "Depends on the model"
        case .piper: "Quality mode"
        }
    }
}
