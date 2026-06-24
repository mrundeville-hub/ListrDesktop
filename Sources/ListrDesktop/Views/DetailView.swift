import SwiftUI

struct DetailView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book?

    var body: some View {
        if let book {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HeroBookPanel(book: book)
                    PlayerPanel(book: book)
                    HStack(alignment: .top, spacing: 18) {
                        ConversionPanel()
                            .frame(minWidth: 420, maxWidth: 520)
                        QueuePanel(book: book)
                            .frame(minWidth: 360)
                    }
                    ChapterPanel(book: book)
                }
                .padding(28)
                .frame(maxWidth: 1160, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
            .navigationTitle(book.title)
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
        }
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Drop a book into sound")
                .font(.system(size: 48, weight: .bold, design: ListrTheme.serif))
            Text("Import FB2, EPUB, or TXT files and prepare chapters for local narration.")
                .font(.system(.title3, design: ListrTheme.mono))
                .foregroundStyle(.secondary)
        }
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct HeroBookPanel: View {
    let book: Book

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text(book.author)
                    .font(.system(.caption, design: ListrTheme.mono).weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Text(book.title)
                    .font(.system(size: 46, weight: .bold, design: ListrTheme.mono))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 24) {
                    Stat(label: "Chapters", value: "\(book.chapterCount)")
                    Stat(label: "Words", value: "\(book.chapters.reduce(0) { $0 + $1.wordCount })")
                    Stat(label: "Status", value: book.status.rawValue)
                    Stat(label: "Duration", value: book.durationLabel)
                }
            }
            .padding(26)

            Spacer()
        }
        .background(ListrTheme.softMint, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PlayerPanel: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("player")
                        .font(.system(.title2, design: ListrTheme.mono).weight(.bold))
                    Text(currentSubtitle)
                        .font(.system(.caption, design: ListrTheme.mono))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        playPrevious()
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .disabled(previousChapter == nil)
                    .help("Previous chapter")

                    Button {
                        playbackStore.skip(seconds: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                    }
                    .disabled(!isCurrentBookLoaded)
                    .help("Back 15 seconds")

                    Button {
                        if isCurrentBookLoaded {
                            playbackStore.togglePlayPause()
                        } else if let chapter = firstPlayableChapter {
                            playbackStore.play(bookID: book.id, chapter: chapter, speed: conversionStore.speed)
                        }
                    } label: {
                        Image(systemName: isCurrentBookLoaded && playbackStore.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(firstPlayableChapter == nil && !isCurrentBookLoaded)
                    .help(isCurrentBookLoaded && playbackStore.isPlaying ? "Pause" : "Play")

                    Button {
                        playbackStore.skip(seconds: 15)
                    } label: {
                        Image(systemName: "goforward.15")
                    }
                    .disabled(!isCurrentBookLoaded)
                    .help("Forward 15 seconds")

                    Button {
                        playNext()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .disabled(nextChapter == nil)
                    .help("Next chapter")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Slider(
                value: Binding(
                    get: { isCurrentBookLoaded ? playbackStore.progress : 0 },
                    set: { playbackStore.seek(to: $0) }
                ),
                in: 0...1
            )
            .disabled(!isCurrentBookLoaded)

            HStack {
                Text(isCurrentBookLoaded ? playbackStore.elapsed.listrTimecode : "00:00")
                Spacer()
                Text(isCurrentBookLoaded ? playbackStore.duration.listrTimecode : "00:00")
            }
            .font(.system(.caption, design: ListrTheme.mono))
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: conversionStore.speed) { _, speed in
            guard isCurrentBookLoaded else { return }
            playbackStore.applySpeed(speed)
        }
    }

    private var playableChapters: [Chapter] {
        book.chapters.filter { chapter in
            guard chapter.status == .ready, let audioPath = chapter.audioPath else { return false }
            return FileManager.default.fileExists(atPath: audioPath)
        }
    }

    private var firstPlayableChapter: Chapter? {
        playableChapters.first
    }

    private var activeChapterIndex: Int? {
        guard isCurrentBookLoaded, let currentChapterID = playbackStore.currentChapterID else { return nil }
        return playableChapters.firstIndex { $0.id == currentChapterID }
    }

    private var previousChapter: Chapter? {
        guard let index = activeChapterIndex, index > 0 else { return nil }
        return playableChapters[index - 1]
    }

    private var nextChapter: Chapter? {
        guard let index = activeChapterIndex, index + 1 < playableChapters.count else { return nil }
        return playableChapters[index + 1]
    }

    private var isCurrentBookLoaded: Bool {
        playbackStore.hasLoadedChapter(for: book.id)
    }

    private var currentSubtitle: String {
        if playbackStore.currentBookID == book.id, !playbackStore.currentTitle.isEmpty {
            return playbackStore.currentTitle
        }
        if let firstPlayableChapter {
            return "Ready: \(firstPlayableChapter.title)"
        }
        return "Convert chapters before playback."
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

private struct ConversionPanel: View {
    @Environment(ConversionStore.self) private var conversionStore

    var body: some View {
        @Bindable var conversionStore = conversionStore

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("narration")
                    .font(.system(.title2, design: ListrTheme.mono).weight(.bold))
                Spacer()
                Text(conversionStore.selectedEngine.loadProfile)
                    .font(.system(.caption, design: ListrTheme.mono).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Picker("Engine", selection: $conversionStore.selectedEngine) {
                ForEach(VoiceEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 14) {
                MetricTile(title: "Speed", value: String(format: "%.2fx", conversionStore.speed), color: ListrTheme.sunYellow)
                MetricTile(title: "Jobs", value: "\(conversionStore.maxParallelJobs)", color: ListrTheme.citrusOrange)
            }

            Slider(value: $conversionStore.speed, in: 0.75...1.35) {
                Text("Speed")
            } minimumValueLabel: {
                Text("0.75")
            } maximumValueLabel: {
                Text("1.35")
            }

            Stepper("Parallel jobs: \(conversionStore.maxParallelJobs)", value: $conversionStore.maxParallelJobs, in: 1...3)
            Toggle("Battery friendly", isOn: $conversionStore.preserveBattery)
            Toggle("Word timings", isOn: $conversionStore.generateWordTimings)

            Label(conversionStore.estimatedLoad, systemImage: "cpu")
                .font(.system(.caption, design: ListrTheme.mono))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(ListrTheme.ink, in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
        .tint(ListrTheme.sunYellow)
    }
}

private struct QueuePanel: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("queue")
                .font(.system(.title2, design: ListrTheme.mono).weight(.bold))

            ProgressView(value: book.progress)
                .tint(.white)

            VStack(spacing: 0) {
                ForEach(queueRows) { chapter in
                    HStack {
                        Text(chapter.title)
                            .font(.system(.body, design: ListrTheme.mono).weight(.bold))
                            .lineLimit(1)
                        Spacer()
                        Text(chapter.status.rawValue)
                            .font(.system(.caption, design: ListrTheme.mono))
                            .opacity(0.75)
                    }
                    .padding(.vertical, 11)
                    Divider().overlay(.white.opacity(0.16))
                }
            }
        }
        .padding(24)
        .background(ListrTheme.electricBlue, in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
    }

    private var queueRows: [Chapter] {
        let chapters = book.chapters.isEmpty ? fallbackChapters : book.chapters
        return Array(chapters.prefix(6))
    }

    private var fallbackChapters: [Chapter] {
        (1...max(book.chapterCount, 1)).map { index in
            Chapter(
                id: UUID(),
                index: index,
                title: "Chapter \(index)",
                text: "",
                status: index <= Int(Double(book.chapterCount) * book.progress) ? .ready : .pending,
                audioPath: nil,
                timingPath: nil
            )
        }
    }
}

private struct ChapterPanel: View {
    let book: Book

    var body: some View {
        let chapters = book.chapters.isEmpty ? fallbackChapters : book.chapters

        VStack(alignment: .leading, spacing: 14) {
            Text("chapters")
                .font(.system(.title, design: ListrTheme.mono).weight(.bold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(chapters.prefix(12)) { chapter in
                    ChapterCard(chapter: chapter)
                }
            }
        }
    }

    private var fallbackChapters: [Chapter] {
        (1...max(book.chapterCount, 1)).map { index in
            Chapter(
                id: UUID(),
                index: index,
                title: "Chapter \(index)",
                text: "",
                status: index <= Int(Double(book.chapterCount) * book.progress) ? .ready : .pending,
                audioPath: nil,
                timingPath: nil
            )
        }
    }
}

private struct ChapterCard: View {
    let chapter: Chapter

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(format: "%02d", chapter.index))
                .font(.system(.caption, design: ListrTheme.mono).weight(.bold))
                .foregroundStyle(.secondary)

            Text(chapter.title)
                .font(.system(.title3, design: ListrTheme.serif).weight(.bold))
                .lineLimit(2)

            Spacer(minLength: 8)

            HStack {
                Text("\(chapter.wordCount) words")
                Spacer()
                Text(chapter.status.rawValue)
            }
            .font(.system(.caption, design: ListrTheme.mono))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(minHeight: 158, alignment: .topLeading)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 8))
    }

    private var cardColor: Color {
        switch chapter.index % 4 {
        case 0: ListrTheme.quietBlue
        case 1: ListrTheme.paperPink.opacity(0.82)
        case 2: ListrTheme.softMint
        default: ListrTheme.sunYellow.opacity(0.82)
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: ListrTheme.mono).weight(.bold))
            Text(value)
                .font(.system(size: 34, weight: .bold, design: ListrTheme.mono))
        }
        .foregroundStyle(.black)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(.caption, design: ListrTheme.mono).weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: ListrTheme.mono).weight(.bold))
        }
    }
}
