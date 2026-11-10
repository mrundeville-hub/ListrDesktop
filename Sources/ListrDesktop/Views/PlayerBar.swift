import SwiftUI

// The one player: transport, position, speed, and the switch to the floating window.
// Shown under an open book, and under the library while something is loaded.
struct PlayerBar: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(OverlayStore.self) private var overlayStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book
    /// Set on the library screen: clicking the title jumps back into the book.
    var onOpenBook: (() -> Void)? = nil

    var body: some View {
        @Bindable var conversionStore = conversionStore

        HStack(spacing: 16) {
            PlayerTransport(book: book)

            VStack(alignment: .leading, spacing: 3) {
                title

                HStack(spacing: 8) {
                    time(playbackStore.elapsed)
                    ListrScrubber(progress: isLoaded ? playbackStore.progress : 0) { progress in
                        playbackStore.seek(to: progress)
                    }
                    .disabled(!isLoaded)
                    time(isLoaded ? playbackStore.duration : 0)
                }
            }
            .frame(minWidth: 150)

            ListrSpeedMenu(speed: $conversionStore.speed) { playbackStore.applySpeed($0) }

            Button {
                overlayStore.toggle()
            } label: {
                Image(systemName: "pip.enter")
            }
            .buttonStyle(ListrIconButtonStyle())
            .help("Floating player: stays on top of other apps")
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.75), in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 24, y: 10)
        .frame(maxWidth: 780)
    }

    private var isLoaded: Bool {
        playbackStore.hasLoadedChapter(for: book.id)
    }

    @ViewBuilder private var title: some View {
        let chapter = isLoaded ? playbackStore.currentTitle : (book.resumeChapter?.title ?? "Nothing to play yet")
        if let onOpenBook {
            Button(action: onOpenBook) {
                (Text(book.title).foregroundStyle(ListrTheme.ink)
                    + Text("  \(chapter)").foregroundStyle(ListrTheme.mutedLabel))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Open this book")
        } else {
            Text(chapter)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ListrTheme.ink)
                .lineLimit(1)
        }
    }

    private func time(_ value: TimeInterval) -> some View {
        Text(value.listrTimecode)
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(ListrTheme.mutedLabel)
    }
}

// Previous / back 15 / play / forward 15 / next. Shared by the bar and the floating player.
struct PlayerTransport: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book
    var playSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 4) {
            button("backward.fill", "Previous chapter", enabled: previous != nil) { play(previous) }
            button("gobackward.15", "Back 15 seconds", enabled: isLoaded) { playbackStore.skip(seconds: -15) }

            Button {
                if isLoaded {
                    playbackStore.togglePlayPause()
                } else {
                    play(book.resumeChapter)
                }
            } label: {
                Image(systemName: isLoaded && playbackStore.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ListrIconButtonStyle(size: playSize, kind: .prominent))
            .disabled(!isLoaded && book.resumeChapter == nil)
            .keyboardShortcut(.space, modifiers: [])
            .help(book.resumeChapter == nil && !isLoaded ? "Convert the book first" : "Play or pause")
            .padding(.horizontal, 4)

            button("goforward.15", "Forward 15 seconds", enabled: isLoaded) { playbackStore.skip(seconds: 15) }
            button("forward.fill", "Next chapter", enabled: next != nil) { play(next) }
        }
    }

    private var isLoaded: Bool {
        playbackStore.hasLoadedChapter(for: book.id)
    }

    private var previous: Chapter? {
        guard isLoaded, let id = playbackStore.currentChapterID else { return nil }
        return book.chapter(before: id)
    }

    private var next: Chapter? {
        guard isLoaded, let id = playbackStore.currentChapterID else { return nil }
        return book.chapter(after: id)
    }

    private func play(_ chapter: Chapter?) {
        guard let chapter else { return }
        playbackStore.play(bookID: book.id, chapter: chapter, speed: conversionStore.speed)
    }

    private func button(_ icon: String, _ help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .buttonStyle(ListrIconButtonStyle())
        .disabled(!enabled)
        .help(help)
    }
}
