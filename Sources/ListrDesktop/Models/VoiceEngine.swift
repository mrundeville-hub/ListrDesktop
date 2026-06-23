import Foundation

enum VoiceEngine: String, CaseIterable, Identifiable, Sendable, Codable {
    case system
    case neuralLocal
    case piper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System Voice"
        case .neuralLocal: "Local Neural"
        case .piper: "Piper Runtime"
        }
    }

    var loadProfile: String {
        switch self {
        case .system: "Lowest load"
        case .neuralLocal: "Balanced"
        case .piper: "Quality mode"
        }
    }
}
