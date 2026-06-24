import AVFoundation
import Foundation
import Observation

enum PlaybackError: LocalizedError {
    case missingAudioFile
    case couldNotLoadAudio

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            "This chapter does not have a generated audio file yet."
        case .couldNotLoadAudio:
            "The generated audio file could not be loaded."
        }
    }
}

@MainActor
@Observable
final class PlaybackStore {
    var currentBookID: Book.ID?
    var currentChapterID: Chapter.ID?
    var currentTitle = ""
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var playbackError: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    var hasLoadedChapter: Bool {
        currentChapterID != nil
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    func play(bookID: Book.ID, chapter: Chapter, speed: Double) {
        guard let audioPath = chapter.audioPath else {
            playbackError = PlaybackError.missingAudioFile.localizedDescription
            return
        }

        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            playbackError = PlaybackError.missingAudioFile.localizedDescription
            return
        }

        do {
            if currentChapterID != chapter.id {
                stopProgressUpdates()
                player = try AVAudioPlayer(contentsOf: audioURL)
                player?.enableRate = true
                player?.prepareToPlay()
                currentBookID = bookID
                currentChapterID = chapter.id
                currentTitle = chapter.title
                duration = player?.duration ?? 0
                elapsed = min(chapter.resumePosition ?? 0, max(duration - 1, 0))
                player?.currentTime = elapsed
            }

            player?.rate = Float(speed)
            player?.play()
            isPlaying = true
            playbackError = nil
            startProgressUpdates()
        } catch {
            playbackError = PlaybackError.couldNotLoadAudio.localizedDescription
        }
    }

    func hasLoadedChapter(for bookID: Book.ID) -> Bool {
        currentBookID == bookID && currentChapterID != nil
    }

    func applySpeed(_ speed: Double) {
        player?.rate = Float(speed)
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            startProgressUpdates()
        }
    }

    func stop() {
        player?.pause()
        isPlaying = false
        stopProgressUpdates()
    }

    func seek(to progress: Double) {
        guard let player else { return }
        let clampedProgress = min(max(progress, 0), 1)
        player.currentTime = duration * clampedProgress
        elapsed = player.currentTime
    }

    func skip(seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(player.currentTime + seconds, 0), duration)
        elapsed = player.currentTime
    }

    private func startProgressUpdates() {
        guard progressTask == nil else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                await MainActor.run {
                    guard let player = self.player else {
                        self.stopProgressUpdates()
                        return
                    }

                    self.elapsed = player.currentTime
                    self.duration = player.duration
                    self.isPlaying = player.isPlaying

                    if !player.isPlaying, self.duration > 0, self.elapsed >= self.duration {
                        self.elapsed = self.duration
                        self.stopProgressUpdates()
                    }
                }
            }
        }
    }

    private func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }
}
