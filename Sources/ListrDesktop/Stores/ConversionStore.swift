import Foundation
import Observation

@Observable
final class ConversionStore {
    var selectedEngine: VoiceEngine = .system
    var speed: Double = 1.0
    var maxParallelJobs: Int = 1
    var preserveBattery: Bool = true
    var generateWordTimings: Bool = true

    var estimatedLoad: String {
        if preserveBattery || maxParallelJobs == 1 {
            return "Light background load"
        }
        return "Faster conversion, higher CPU use"
    }
}
