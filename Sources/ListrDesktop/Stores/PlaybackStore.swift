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
    var currentText = ""

    /// Called when a chapter plays to the end; wired by the app to auto-advance.
    @ObservationIgnored var onChapterFinished: ((Book.ID, Chapter.ID) -> Void)?
    /// Called while audio is playing with the real seconds that just passed; feeds the stats.
    @ObservationIgnored var onListened: ((TimeInterval) -> Void)?
    @ObservationIgnored private var lastTick = Date()

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var currentTiming: ChapterTiming?
    @ObservationIgnored private let playerDelegate = PlayerFinishDelegate()

    var hasLoadedChapter: Bool {
        currentChapterID != nil
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var currentWord: ChapterWordTiming? {
        // A touch ahead of the clock: the position is sampled every 0.1 s, and a highlight that
        // lands just before the word is heard reads as in sync, one that lands after reads as late.
        currentTiming?.word(at: elapsed + 0.08)
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
                playerDelegate.onFinish = { [weak self] in
                    Task { @MainActor in self?.handleChapterFinished() }
                }
                player?.delegate = playerDelegate
                player?.enableRate = true
                player?.prepareToPlay()
                currentBookID = bookID
                currentChapterID = chapter.id
                currentTitle = chapter.title
                currentText = chapter.text
                duration = player?.duration ?? 0
                elapsed = min(chapter.resumePosition ?? 0, max(duration - 1, 0))
                player?.currentTime = elapsed
                currentTiming = loadTiming(for: chapter, duration: duration)
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

    /// Drops the loaded chapter entirely — used when its audio is about to be deleted.
    func unload() {
        stop()
        player = nil
        currentTiming = nil
        currentBookID = nil
        currentChapterID = nil
        currentTitle = ""
        currentText = ""
        elapsed = 0
        duration = 0
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
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                await MainActor.run {
                    guard let player = self.player else {
                        self.stopProgressUpdates()
                        return
                    }

                    let now = Date()
                    if player.isPlaying {
                        self.onListened?(min(now.timeIntervalSince(self.lastTick), 1))
                    }
                    self.lastTick = now

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

    private func handleChapterFinished() {
        elapsed = duration
        isPlaying = false
        stopProgressUpdates()
        guard let bookID = currentBookID, let chapterID = currentChapterID else { return }
        onChapterFinished?(bookID, chapterID)
    }

    private func loadTiming(for chapter: Chapter, duration: TimeInterval) -> ChapterTiming {
        if
            let timingPath = chapter.timingPath,
            let data = try? Data(contentsOf: URL(fileURLWithPath: timingPath)),
            let timing = try? JSONDecoder().decode(ChapterTiming.self, from: data)
        {
            return timing
        }

        return ChapterTimingBuilder.build(text: chapter.text, duration: duration)
    }
}

// AVAudioPlayer needs an NSObject delegate; PlaybackStore is a plain Observable class.
private final class PlayerFinishDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
