import AVFoundation
import Foundation
import Observation

/// Synthesizes one short sentence with the current settings and plays it, so a voice can be
/// judged in a few seconds instead of after converting a whole book.
@MainActor
@Observable
final class VoicePreviewService {
    static let sampleText = "Утро было ясное, и город просыпался медленно, будто нехотя."

    private(set) var isRunning = false
    var errorMessage: String?

    @ObservationIgnored private let ttsService: any TTSService
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var lastSampleURL: URL?

    init(ttsService: any TTSService = SystemTTSService()) {
        self.ttsService = ttsService
    }

    func play(configuration: TTSConfiguration) async {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }

        player?.stop()
        // The previous sample is only safe to delete once nothing is playing it.
        if let lastSampleURL {
            try? FileManager.default.removeItem(at: lastSampleURL)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("listr-preview-\(UUID().uuidString).\(configuration.outputFileExtension)")

        do {
            let audioURL = try await ttsService.synthesize(
                chapterText: Self.sampleText,
                configuration: configuration,
                to: outputURL
            )
            let player = try AVAudioPlayer(contentsOf: audioURL)
            self.player = player
            lastSampleURL = audioURL
            player.play()
        } catch {
            errorMessage = error.localizedDescription
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
}
