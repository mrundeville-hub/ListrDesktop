import SwiftUI

struct DetailView: View {
    let book: Book?

    var body: some View {
        if let book {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HeroBookPanel(book: book)
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
            Text("Import FB2 or EPUB and Listr will prepare chapters for local narration.")
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
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ListrTheme.sunYellow
                ListrTheme.softMint
                ListrTheme.paperPink
            }
            .frame(width: 54)
        }
        .frame(minHeight: 250)
        .background(ListrTheme.softMint.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(.black)
                .frame(width: 7, height: 7)
                .padding(26)
        }
    }
}

private struct ConversionPanel: View {
    @Environment(ConversionStore.self) private var conversionStore

    var body: some View {
        @Bindable var conversionStore = conversionStore

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
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
        .background(ListrTheme.electricBlue, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }

    private var queueRows: [Chapter] {
        let chapters = book.chapters.isEmpty ? fallbackChapters : book.chapters
        return Array(chapters.prefix(6))
    }

    private var fallbackChapters: [Chapter] {
        (1...max(book.chapterCount, 1)).map { index in
            Chapter(id: UUID(), index: index, title: "Chapter \(index)", text: "", status: index <= Int(Double(book.chapterCount) * book.progress) ? .ready : .pending, audioPath: nil, timingPath: nil)
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
            Chapter(id: UUID(), index: index, title: "Chapter \(index)", text: "", status: index <= Int(Double(book.chapterCount) * book.progress) ? .ready : .pending, audioPath: nil, timingPath: nil)
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
                .textCase(.uppercase)
            Text(value)
                .font(.system(.headline, design: ListrTheme.mono).weight(.bold))
        }
    }
}
