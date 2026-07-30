import SwiftUI

struct DetailView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book?

    var body: some View {
        if let book {
            FullscreenReadingWorkspace(book: book)
            .onChange(of: playbackStore.elapsed) { _, elapsed in
                guard
                    playbackStore.currentBookID == book.id,
                    let chapterID = playbackStore.currentChapterID
                else {
                    return
                }
                libraryStore.updatePlaybackPosition(bookID: book.id, chapterID: chapterID, position: elapsed)
            }
        } else {
            EmptyLibraryView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FullscreenReadingWorkspace: View {
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                ReaderCanvasPanel(book: book)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                FloatingReadingControls(book: book)
            }

            FindingsRail(book: book)
                .frame(width: 300)
                .frame(maxHeight: .infinity)
        }
    }
}

private struct ReaderCanvasPanel: View {
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ListrChip(
                    text: "Now reading",
                    icon: "text.book.closed.fill",
                    fill: ListrTheme.accentWash,
                    tint: ListrTheme.accent
                )

                Text(book.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ListrTheme.mutedLabel)
                    .lineLimit(1)

                Spacer()

                ListrChip(text: "\(Int(playbackStore.progress * 100))%", icon: "chart.pie.fill")
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(highlightedPassage)
                        .font(.system(size: 26, weight: .regular))
                        .lineSpacing(11)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("reader-text")
                        .padding(.horizontal, 30)
                        .padding(.top, 26)
                        .padding(.bottom, 40)
                }
                .onChange(of: playbackStore.currentWord?.index) { _, _ in
                    withAnimation(.smooth(duration: 0.28)) {
                        proxy.scrollTo("reader-text", anchor: .center)
                    }
                }
            }
        }
        .listrCard()
    }

    private var highlightedPassage: AttributedString {
        guard !playbackStore.currentText.isEmpty else {
            var empty = AttributedString("Convert a chapter, press play, and the spoken words will appear here.")
            empty.foregroundColor = ListrTheme.mutedLabel
            return empty
        }

        guard
            let word = playbackStore.currentWord,
            let stringRange = Range(NSRange(location: word.location, length: word.length), in: playbackStore.currentText)
        else {
            var preview = AttributedString(compactPreview(playbackStore.currentText))
            preview.foregroundColor = ListrTheme.ink.opacity(0.55)
            return preview
        }

        let source = playbackStore.currentText
        let snippetStart = source.index(stringRange.lowerBound, offsetBy: -520, limitedBy: source.startIndex) ?? source.startIndex
        let snippetEnd = source.index(stringRange.upperBound, offsetBy: 900, limitedBy: source.endIndex) ?? source.endIndex
        let prefix = snippetStart == source.startIndex ? "" : "..."
        let suffix = snippetEnd == source.endIndex ? "" : "..."
        let snippet = prefix + String(source[snippetStart..<snippetEnd]) + suffix

        var attributed = AttributedString(snippet)
        attributed.foregroundColor = ListrTheme.ink.opacity(0.4)

        let highlightStartOffset = source.distance(from: snippetStart, to: stringRange.lowerBound) + prefix.count
        let highlightEndOffset = source.distance(from: snippetStart, to: stringRange.upperBound) + prefix.count
        if
            let highlightStart = snippet.index(snippet.startIndex, offsetBy: highlightStartOffset, limitedBy: snippet.endIndex),
            let highlightEnd = snippet.index(snippet.startIndex, offsetBy: highlightEndOffset, limitedBy: snippet.endIndex),
            let lower = AttributedString.Index(highlightStart, within: attributed),
            let upper = AttributedString.Index(highlightEnd, within: attributed) {
            attributed[lower..<upper].foregroundColor = ListrTheme.accent
            attributed[lower..<upper].backgroundColor = ListrTheme.accentWash
            attributed[lower..<upper].font = .system(size: 26, weight: .semibold)
        }

        return attributed
    }

    private func compactPreview(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .prefix(1400)
            .description
    }
}

private struct FindingsRail: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Chapters")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ListrTheme.ink)
                Spacer()
                ListrChip(text: "\(railRows.count)")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(railRows) { chapter in
                        ChapterRow(book: book, chapter: chapter)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .listrCard()
    }

    private var railRows: [Chapter] {
        book.chapters.isEmpty ? fallbackChapters : book.chapters
    }

    private var fallbackChapters: [Chapter] {
        (1...max(book.chapterCount, 1)).map { index in
            Chapter(id: UUID(), index: index, title: "Chapter \(index)", text: "", status: .pending, audioPath: nil, timingPath: nil)
        }
    }
}

private struct ChapterRow: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book
    let chapter: Chapter

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Image(systemName: isActive && playbackStore.isPlaying ? "waveform" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isPlayable || isActive ? Color.white : ListrTheme.mutedLabel)
                    .frame(width: 30, height: 30)
                    .background(isPlayable || isActive ? ListrTheme.ink : ListrTheme.chip, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isPlayable ? ListrTheme.ink : ListrTheme.mutedLabel)
                        .lineLimit(1)

                    if let lastError = chapter.lastError {
                        Text(lastError)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                statusChip
                    .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive ? ListrTheme.chip : .clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isPlayable)
        .help(helpText)
    }

    private var helpText: String {
        if let lastError = chapter.lastError { return lastError }
        return isPlayable ? "Play this chapter" : "Convert the book to unlock playback"
    }

    @ViewBuilder private var statusChip: some View {
        switch chapter.status {
        case .ready:
            ListrChip(text: "Ready", icon: "checkmark", fill: ListrTheme.chip, tint: ListrTheme.ink)
        case .converting:
            ListrChip(text: "Converting", icon: "waveform", fill: ListrTheme.accentWash, tint: ListrTheme.accent)
        case .failed:
            ListrChip(text: "Failed", icon: "exclamationmark.triangle.fill", fill: Color.red.opacity(0.1), tint: .red)
        case .pending:
            EmptyView() // muted row + gray play already read as "not ready"
        }
    }

    private var isPlayable: Bool { chapter.isReady }

    private var isActive: Bool {
        playbackStore.currentBookID == book.id && playbackStore.currentChapterID == chapter.id
    }

    private func play() {
        if isActive {
            playbackStore.togglePlayPause()
        } else {
            playbackStore.play(bookID: book.id, chapter: chapter, speed: conversionStore.speed)
        }
    }
}

private struct FloatingReadingControls: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(OverlayStore.self) private var overlayStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book

    @State private var isConfirmingRegenerate = false

    var body: some View {
        @Bindable var conversionStore = conversionStore

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ListrChip(text: activeTitle, icon: "book.fill")
                ListrChip(text: "\(playbackStore.elapsed.listrTimecode) / \(playbackStore.duration.listrTimecode)", icon: "clock")

                Spacer()

                ListrSpeedMenu(speed: $conversionStore.speed) { playbackStore.applySpeed($0) }

                Text("listr")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ListrTheme.mutedLabel)
            }

            ListrScrubber(progress: playbackStore.progress) { progress in
                playbackStore.seek(to: progress)
            }
            .disabled(!isCurrentBookLoaded)

            HStack(spacing: 10) {
                RoundControl("backward.end.fill", disabled: previousChapter == nil, help: "Previous chapter", action: playPrevious)
                RoundControl("gobackward.15", disabled: !isCurrentBookLoaded, help: "Back 15 seconds") {
                    playbackStore.skip(seconds: -15)
                }
                Button {
                    if isCurrentBookLoaded {
                        playbackStore.togglePlayPause()
                    } else if let chapter = firstPlayableChapter {
                        playbackStore.play(bookID: book.id, chapter: chapter, speed: conversionStore.speed)
                    }
                } label: {
                    Image(systemName: isCurrentBookLoaded && playbackStore.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 46, height: 46)
                        .foregroundStyle(.white)
                        .background(ListrTheme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(firstPlayableChapter == nil && !isCurrentBookLoaded)
                .keyboardShortcut(.space, modifiers: [])
                .help("Play or pause")
                RoundControl("goforward.15", disabled: !isCurrentBookLoaded, help: "Forward 15 seconds") {
                    playbackStore.skip(seconds: 15)
                }
                RoundControl("forward.end.fill", disabled: nextChapter == nil, help: "Next chapter", action: playNext)
                RoundControl(overlayStore.isPresented ? "macwindow.badge.plus" : "macwindow", disabled: false, help: "Toggle reading overlay") {
                    overlayStore.toggle()
                }

                Spacer()

                if libraryStore.isConverting {
                    Button("Cancel") { libraryStore.cancelConversion() }
                        .buttonStyle(ListrPillButtonStyle(prominent: false))
                        .help("Stop conversion")
                } else {
                    if libraryStore.canRegenerateSelectedBook {
                        Button("Regenerate") { isConfirmingRegenerate = true }
                            .buttonStyle(ListrPillButtonStyle(prominent: false))
                            .help("Delete generated audio and convert again")
                    }

                    if libraryStore.canConvertSelectedBook {
                        Button("Convert") {
                            libraryStore.convertSelectedBook(configuration: conversionStore.activeConfiguration)
                        }
                        .buttonStyle(ListrPillButtonStyle())
                        .help("Convert chapters to audio")
                    }
                }
            }
        }
        .padding(20)
        .listrCard()
        .confirmationDialog(
            "Regenerate audio for “\(book.title)”?",
            isPresented: $isConfirmingRegenerate,
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) {
                if playbackStore.currentBookID == book.id {
                    playbackStore.unload()
                }
                libraryStore.regenerateSelectedBook(configuration: conversionStore.activeConfiguration)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing audio and word timings for this book are deleted and rebuilt from scratch.")
        }
    }

    private var firstPlayableChapter: Chapter? { book.playableChapters.first }

    private var currentChapterID: Chapter.ID? {
        isCurrentBookLoaded ? playbackStore.currentChapterID : nil
    }

    private var previousChapter: Chapter? {
        currentChapterID.flatMap { book.chapter(before: $0) }
    }

    private var nextChapter: Chapter? {
        currentChapterID.flatMap { book.chapter(after: $0) }
    }

    private var isCurrentBookLoaded: Bool {
        playbackStore.hasLoadedChapter(for: book.id)
    }

    private var activeTitle: String {
        if playbackStore.currentBookID == book.id, !playbackStore.currentTitle.isEmpty {
            return playbackStore.currentTitle
        }
        if let firstPlayableChapter {
            return firstPlayableChapter.title
        }
        return "No audio ready yet"
    }

    private func playPrevious() {
        guard let previousChapter else { return }
        playbackStore.play(bookID: book.id, chapter: previousChapter, speed: conversionStore.speed)
    }

    private func playNext() {
        guard let nextChapter else { return }
        playbackStore.play(bookID: book.id, chapter: nextChapter, speed: conversionStore.speed)
    }
}

private struct RoundControl: View {
    let icon: String
    let disabled: Bool
    let help: String
    let action: () -> Void

    init(_ icon: String, disabled: Bool, help: String, action: @escaping () -> Void) {
        self.icon = icon
        self.disabled = disabled
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(ListrTheme.ink)
                .background(ListrTheme.chip, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(help)
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ListrChip(
                text: "Welcome",
                icon: "sparkles",
                fill: ListrTheme.accentWash,
                tint: ListrTheme.accent
            )
            Text("Drop a book into sound")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(ListrTheme.ink)
            Text("Import FB2, EPUB, or TXT and turn it into a tiny local talking book.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(ListrTheme.mutedLabel)
        }
        .padding(36)
        .frame(maxWidth: 520, alignment: .leading)
        .listrCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
