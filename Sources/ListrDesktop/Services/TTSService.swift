import Foundation

protocol TTSService {
    func synthesize(chapterText: String, using engine: VoiceEngine) async throws -> URL
}

struct PlannedTTSService: TTSService {
    func synthesize(chapterText: String, using engine: VoiceEngine) async throws -> URL {
        throw CocoaError(.featureUnsupported)
    }
}
