import AVFoundation
import Foundation
import MediaPlayer
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
    var sleepTimer = SleepTimer.off

    enum SleepTimer: Equatable {
        case off
        case at(Date)
        case endOfChapter
    }

    /// Called when a chapter plays to the end; wired by the app to auto-advance.
    @ObservationIgnored var onChapterFinished: ((Book.ID, Chapter.ID) -> Void)?
    /// Called while audio is playing with the real seconds that just passed; feeds the stats.
    @ObservationIgnored var onListened: ((TimeInterval) -> Void)?
    /// Called by the keyboard / headphone "next" (+1) and "previous" (-1) keys.
    @ObservationIgnored var onSkipChapter: ((Int) -> Void)?
    @ObservationIgnored private var lastTick = Date()

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var currentTiming: ChapterTiming?
    @ObservationIgnored private let playerDelegate = PlayerFinishDelegate()

    init() {
        connectMediaKeys()
    }

    var hasLoadedChapter: Bool {
        currentChapterID != nil
    }

    /// The words of the loaded chapter that start inside `range` (UTF-16 offsets into its text).
    func words(in range: NSRange) -> [ChapterWordTiming] {
        currentTiming?.words.filter { $0.location >= range.location && $0.location < range.location + range.length } ?? []
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
            publishNowPlaying()
        } catch {
            playbackError = PlaybackError.couldNotLoadAudio.localizedDescription
        }
    }

    func hasLoadedChapter(for bookID: Book.ID) -> Bool {
        currentBookID == bookID && currentChapterID != nil
    }

    func applySpeed(_ speed: Double) {
        player?.rate = Float(speed)
        publishNowPlaying()
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
        publishNowPlaying()
    }

    func stop() {
        player?.pause()
        isPlaying = false
        stopProgressUpdates()
        publishNowPlaying()
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
        sleepTimer = .off
        publishNowPlaying()
    }

    func seek(to progress: Double) {
        guard let player else { return }
        let clampedProgress = min(max(progress, 0), 1)
        player.currentTime = duration * clampedProgress
        elapsed = player.currentTime
        publishNowPlaying()
    }

    func seek(toTime time: TimeInterval) {
        guard duration > 0 else { return }
        seek(to: time / duration)
    }

    func skip(seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(player.currentTime + seconds, 0), duration)
        elapsed = player.currentTime
        publishNowPlaying()
    }

    func sleep(afterMinutes minutes: Int) {
        sleepTimer = .at(Date().addingTimeInterval(Double(minutes) * 60))
    }

    // MARK: Media keys and Now Playing

    /// Keyboard media keys, headphone buttons and Control Centre all arrive through here.
    private func connectMediaKeys() {
        let commands = MPRemoteCommandCenter.shared()
        // MediaPlayer does not promise a thread for these, so each one hops to the main actor.
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (PlaybackStore, TimeInterval) -> Void) {
            command.addTarget { [weak self] event in
                let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
                Task { @MainActor in
                    guard let self, self.hasLoadedChapter else { return }
                    action(self, position)
                }
                return .success
            }
        }

        on(commands.playCommand) { store, _ in if !store.isPlaying { store.togglePlayPause() } }
        on(commands.pauseCommand) { store, _ in if store.isPlaying { store.togglePlayPause() } }
        on(commands.togglePlayPauseCommand) { store, _ in store.togglePlayPause() }
        on(commands.nextTrackCommand) { store, _ in store.onSkipChapter?(1) }
        on(commands.previousTrackCommand) { store, _ in store.onSkipChapter?(-1) }
        commands.skipForwardCommand.preferredIntervals = [15]
        on(commands.skipForwardCommand) { store, _ in store.skip(seconds: 15) }
        commands.skipBackwardCommand.preferredIntervals = [15]
        on(commands.skipBackwardCommand) { store, _ in store.skip(seconds: -15) }
        on(commands.changePlaybackPositionCommand) { store, position in store.seek(toTime: position) }
    }

    private func publishNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard hasLoadedChapter else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(player?.rate ?? 1) : 0
        ]
        center.playbackState = isPlaying ? .playing : .paused // macOS routes the keys by this
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

                    if case .at(let deadline) = self.sleepTimer, now >= deadline {
                        self.sleepTimer = .off
                        if player.isPlaying { self.togglePlayPause() }
                    }

                    // Only real changes: every write wakes each view that reads the property.
                    self.elapsed = player.currentTime
                    if self.duration != player.duration { self.duration = player.duration }
                    if self.isPlaying != player.isPlaying { self.isPlaying = player.isPlaying }

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
        publishNowPlaying()
        if sleepTimer == .endOfChapter {
            sleepTimer = .off // stay here; pressing play later moves on to the next chapter
            return
        }
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
