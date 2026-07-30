import SwiftUI

struct PlaybackOverlayView: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(OverlayStore.self) private var overlayStore
    @Environment(PlaybackStore.self) private var playbackStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            header
            readerSection
            playerSection
        }
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 520, minHeight: 620, idealHeight: 720)
        .background(ListrTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 28, y: 14)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .padding(24) // room for the soft shadow inside the transparent panel
    }

    // MARK: Top bar — violet reader chip left, close right

    private var topBar: some View {
        HStack {
            ListrChip(
                text: "Reading",
                icon: "text.book.closed.fill",
                fill: ListrTheme.accentWash,
                tint: ListrTheme.accent
            )

            Spacer()

            Text("listr")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ListrTheme.mutedLabel)

            Button {
                overlayStore.isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ListrTheme.mutedLabel)
                    .frame(width: 24, height: 24)
                    .background(ListrTheme.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close overlay")
            .padding(.leading, 6)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: Header — title + meta chips

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ListrTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ListrChip(text: timeLabel, icon: "clock")
                ListrChip(text: "\(Int(playbackStore.progress * 100))%", icon: "chart.pie.fill")

                Spacer(minLength: 0)

                @Bindable var conversionStore = conversionStore
                ListrSpeedMenu(speed: $conversionStore.speed) { playbackStore.applySpeed($0) }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    // MARK: Reader — spoken word washed in violet

    private var readerSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(readingText)
                    .lineSpacing(9)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("reading-text")
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: playbackStore.currentWord?.index) { _, _ in
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo("reading-text", anchor: .center)
                }
            }
        }
    }

    // MARK: Player — gray pill skips, black circle play

    private var playerSection: some View {
        VStack(spacing: 16) {
            ListrScrubber(progress: playbackStore.progress) { progress in
                playbackStore.seek(to: progress)
            }
            .disabled(!playbackStore.hasLoadedChapter)

            HStack(spacing: 10) {
                controlButton(systemName: "backward.end.fill", enabled: previousChapter != nil) {
                    play(previousChapter)
                }
                .help("Previous chapter")

                controlButton(systemName: "gobackward.15") {
                    playbackStore.skip(seconds: -15)
                }
                .help("Back 15 seconds")

                Button {
                    playbackStore.togglePlayPause()
                } label: {
                    Image(systemName: playbackStore.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.white)
                        .background(ListrTheme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!playbackStore.hasLoadedChapter)
                .help("Play or pause")

                controlButton(systemName: "goforward.15") {
                    playbackStore.skip(seconds: 15)
                }
                .help("Forward 15 seconds")

                controlButton(systemName: "forward.end.fill", enabled: nextChapter != nil) {
                    play(nextChapter)
                }
                .help("Next chapter")

                Spacer(minLength: 0)

                ListrChip(text: playbackStore.elapsed.listrTimecode)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
    }

    private func controlButton(systemName: String, enabled: Bool? = nil, action: @escaping () -> Void) -> some View {
        let isEnabled = enabled ?? playbackStore.hasLoadedChapter
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(ListrTheme.ink)
                .background(ListrTheme.chip, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    // MARK: Chapter navigation

    private var currentBook: Book? {
        guard let bookID = playbackStore.currentBookID else { return nil }
        return libraryStore.books.first { $0.id == bookID }
    }

    private var previousChapter: Chapter? {
        guard let chapterID = playbackStore.currentChapterID else { return nil }
        return currentBook?.chapter(before: chapterID)
    }

    private var nextChapter: Chapter? {
        guard let chapterID = playbackStore.currentChapterID else { return nil }
        return currentBook?.chapter(after: chapterID)
    }

    private func play(_ chapter: Chapter?) {
        guard let chapter, let bookID = playbackStore.currentBookID else { return }
        playbackStore.play(bookID: bookID, chapter: chapter, speed: conversionStore.speed)
    }

    // MARK: Content

    private var title: String {
        playbackStore.currentTitle.isEmpty ? "Open a book and start narration" : playbackStore.currentTitle
    }

    private var timeLabel: String {
        "\(playbackStore.elapsed.listrTimecode) / \(playbackStore.duration.listrTimecode)"
    }

    private var readingText: AttributedString {
        let bodyFont = Font.system(size: 21, weight: .regular)

        guard !playbackStore.currentText.isEmpty else {
            var value = AttributedString("Start playback to see each spoken word highlighted here.")
            value.foregroundColor = ListrTheme.mutedLabel
            value.font = bodyFont
            return value
        }

        guard
            let word = playbackStore.currentWord,
            let stringRange = Range(NSRange(location: word.location, length: word.length), in: playbackStore.currentText)
        else {
            return passageAroundCurrentPosition(font: bodyFont)
        }

        let source = playbackStore.currentText
        let snippetStart = source.index(stringRange.lowerBound, offsetBy: -280, limitedBy: source.startIndex) ?? source.startIndex
        let snippetEnd = source.index(stringRange.upperBound, offsetBy: 460, limitedBy: source.endIndex) ?? source.endIndex
        let prefix = snippetStart == source.startIndex ? "" : "…"
        let suffix = snippetEnd == source.endIndex ? "" : "…"
        let snippetBody = source[snippetStart..<snippetEnd]
        let snippet = prefix + String(snippetBody) + suffix

        var attributed = AttributedString(snippet)
        attributed.foregroundColor = ListrTheme.ink.opacity(0.45)
        attributed.font = bodyFont

        let highlightStartOffset = source.distance(from: snippetStart, to: stringRange.lowerBound) + prefix.count
        let highlightEndOffset = source.distance(from: snippetStart, to: stringRange.upperBound) + prefix.count
        if
            let highlightStart = snippet.index(snippet.startIndex, offsetBy: highlightStartOffset, limitedBy: snippet.endIndex),
            let highlightEnd = snippet.index(snippet.startIndex, offsetBy: highlightEndOffset, limitedBy: snippet.endIndex),
            let lower = AttributedString.Index(highlightStart, within: attributed),
            let upper = AttributedString.Index(highlightEnd, within: attributed) {
            attributed[lower..<upper].backgroundColor = ListrTheme.accentWash
            attributed[lower..<upper].foregroundColor = ListrTheme.accent
            attributed[lower..<upper].font = .system(size: 21, weight: .semibold)
        }

        return attributed
    }

    private func passageAroundCurrentPosition(font: Font) -> AttributedString {
        let cleaned = playbackStore.currentText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        var attributed = AttributedString(String(cleaned.prefix(720)))
        attributed.foregroundColor = ListrTheme.ink
        attributed.font = font
        return attributed
    }
}
