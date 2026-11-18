import SwiftUI

// The one player: transport, position, speed, and the switch to the floating window.
// A glass capsule floating over the bottom of the library and of an open book.
struct PlayerBar: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(OverlayStore.self) private var overlayStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book
    /// Set on the library screen: clicking the title jumps back into the book.
    var onOpenBook: (() -> Void)? = nil

    var body: some View {
        @Bindable var conversionStore = conversionStore

        HStack(spacing: 14) {
            if onOpenBook != nil {
                // On the library screen the bar may be offering a book that is not loaded yet.
                ListrCover(seed: book.title, imagePath: book.coverPath, cornerRadius: 3)
                    .frame(width: 27, height: 36)
            }

            PlayerTransport(book: book)

            VStack(alignment: .leading, spacing: 3) {
                title

                PlayerProgress(isLoaded: isLoaded)
            }
            .frame(minWidth: 80)

            ListrSpeedMenu(speed: $conversionStore.speed) { playbackStore.applySpeed($0) }

            ListrSleepMenu()

            Button {
                overlayStore.toggle()
            } label: {
                Image(systemName: "pip.enter")
            }
            .buttonStyle(ListrIconButtonStyle())
            .help("Floating player: stays on top of other apps")
        }
        .padding(.leading, onOpenBook != nil ? 8 : 12)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .listrGlass(in: Capsule())
        .frame(maxWidth: 760)
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

}

// Time and scrubber. Its own view so the 10 Hz clock redraws only this row, not the whole player.
struct PlayerProgress: View {
    @Environment(PlaybackStore.self) private var playbackStore

    let isLoaded: Bool

    var body: some View {
        HStack(spacing: 8) {
            time(isLoaded ? playbackStore.elapsed : 0)
            ListrScrubber(progress: isLoaded ? playbackStore.progress : 0) { progress in
                playbackStore.seek(to: progress)
            }
            .disabled(!isLoaded)
            time(isLoaded ? playbackStore.duration : 0)
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

extension View {
    /// Floats the player over the bottom edge; the screen's content runs on underneath it.
    /// An overlay, not a safe-area inset: an inset's minimum width becomes the split view column's,
    /// and next to the chapter inspector that sent AppKit into an endless constraint loop (crash).
    func listrPlayerBar(_ book: Book?, onOpenBook: (() -> Void)? = nil) -> some View {
        safeAreaPadding(.bottom, book == nil ? 0 : 76)
            .overlay(alignment: .bottom) {
                if let book {
                    PlayerBar(book: book, onOpenBook: onOpenBook)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    /// Liquid Glass on macOS 26 and later, frosted material before it.
    @ViewBuilder func listrGlass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.15), radius: 18, y: 6)
        }
    }
}
