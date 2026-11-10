import SwiftUI

// One open book: the text being read in the middle, chapters on the right, player underneath.
struct BookView: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book
    let onBack: () -> Void
    let onRemove: () -> Void

    @AppStorage("book.showsChapters") private var showsChapters = true
    @State private var isConfirmingRegenerate = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                HStack(spacing: 20) {
                    reader
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsChapters, ListrAdaptiveLayout.showsFindingsRail(forAvailableWidth: geo.size.width) {
                        ChapterList(book: book)
                            .frame(width: ListrAdaptiveLayout.findingsRailWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            PlayerBar(book: book)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .animation(.smooth(duration: 0.3), value: showsChapters)
        .animation(.smooth(duration: 0.3), value: isReading)
        .onExitCommand(perform: onBack)
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
            Text("The current audio is deleted and every chapter is converted again with the voice chosen in Settings.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        ListrTopBar(title: book.title, subtitle: book.author) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(ListrIconButtonStyle())
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to the library")
        } trailing: {
            conversionControl

            Button {
                showsChapters.toggle()
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(ListrIconButtonStyle(kind: showsChapters ? .filled : .plain))
            .help(showsChapters ? "Hide chapters" : "Show chapters")

            Menu {
                Button("Regenerate Audio…") { isConfirmingRegenerate = true }
                    .disabled(!libraryStore.canRegenerateSelectedBook)
                Divider()
                Button("Remove from Library…", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ListrTheme.ink)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
    }

    // Conversion lives in one place: progress with a stop button while it runs,
    // "Convert the rest" when the book is only partly done, nothing once it is finished.
    @ViewBuilder private var conversionControl: some View {
        if libraryStore.isConvertingSelectedBook {
            HStack(spacing: 8) {
                ProgressView(value: book.progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("\(readyCount) of \(book.chapters.count)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(ListrTheme.ink)
                    .contentTransition(.numericText())
                Button {
                    libraryStore.cancelConversion()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(ListrIconButtonStyle(size: 22, kind: .filled))
                .help("Stop converting. Finished chapters are kept.")
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(height: 30)
            .background(ListrTheme.fill, in: Capsule())
            .animation(.snappy, value: readyCount)
        } else if libraryStore.canConvertSelectedBook, book.resumeChapter != nil {
            Button("Convert the rest", action: convert)
                .buttonStyle(ListrCapsuleButtonStyle())
                .help("\(book.chapters.count - readyCount) chapters are not converted yet")
        }
    }

    private var readyCount: Int {
        Int((book.progress * Double(book.chapters.count)).rounded())
    }

    private func convert() {
        libraryStore.convertSelectedBook(configuration: conversionStore.activeConfiguration)
    }

    // MARK: Reader

    private var isReading: Bool {
        playbackStore.hasLoadedChapter(for: book.id) && !playbackStore.currentText.isEmpty
    }

    @ViewBuilder private var reader: some View {
        if isReading {
            ScrollView {
                Text(playbackStore.highlightedSnippet(fontSize: 22, before: 520, after: 900))
                    .lineSpacing(10)
                    .textSelection(.enabled)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            }
            .scrollIndicators(.hidden)
            .transition(.opacity)
        } else {
            hero
                .transition(.opacity)
        }
    }

    // Before anything plays: the book itself and the single next step.
    private var hero: some View {
        VStack(spacing: 24) {
            ListrCover(seed: book.title, cornerRadius: 24)
                .frame(width: 168, height: 224)
                .shadow(color: .black.opacity(0.12), radius: 24, y: 12)

            VStack(spacing: 4) {
                Text(book.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ListrTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(book.author)
                    .font(.system(size: 14))
                    .foregroundStyle(ListrTheme.mutedLabel)
            }

            heroAction
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var heroAction: some View {
        if let chapter = book.resumeChapter {
            Button {
                playbackStore.play(bookID: book.id, chapter: chapter, speed: conversionStore.speed)
            } label: {
                Label((chapter.resumePosition ?? 0) > 0 ? "Continue \(chapter.title)" : "Play", systemImage: "play.fill")
            }
            .buttonStyle(ListrCapsuleButtonStyle(prominent: true, large: true))
        } else if libraryStore.isConvertingSelectedBook {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                hint("Converting the first chapter. You can start listening as soon as it is ready.")
            }
        } else if libraryStore.canConvertSelectedBook {
            VStack(spacing: 12) {
                Button("Convert to audio", action: convert)
                    .buttonStyle(ListrCapsuleButtonStyle(prominent: true, large: true))
                if let error = book.chapters.compactMap(\.lastError).first {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .textSelection(.enabled)
                } else {
                    hint("Read by the \(conversionStore.selectedEngine.title) voice. Chapters unlock one by one.")
                }
            }
        } else {
            hint("Another book is converting. This one can start when it finishes.")
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(ListrTheme.mutedLabel)
            .multilineTextAlignment(.center)
    }
}

private struct ChapterList: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Chapters")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ListrTheme.ink)
                Spacer()
                Text(summary)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(ListrTheme.mutedLabel)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(book.chapters) { chapter in
                        ChapterRow(book: book, chapter: chapter)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var summary: String {
        let total = book.chapters.count
        let ready = Int((book.progress * Double(total)).rounded())
        return ready == total ? "\(total)" : "\(ready) of \(total) ready"
    }
}

private struct ChapterRow: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book
    let chapter: Chapter

    @State private var isHovered = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 10) {
                Group {
                    if isActive {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: playbackStore.isPlaying)
                            .foregroundStyle(ListrTheme.ink)
                    } else {
                        Text("\(chapter.index)")
                            .monospacedDigit()
                            .foregroundStyle(ListrTheme.mutedLabel)
                    }
                }
                .font(.system(size: 12))
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(ListrTheme.ink)
                        .lineLimit(1)

                    if let lastError = chapter.lastError {
                        Text(lastError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 6)

                if chapter.status == .converting {
                    ProgressView()
                        .controlSize(.small)
                } else if chapter.status == .failed {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ListrTheme.ink.opacity(isActive ? 0.07 : isHovered && isPlayable ? 0.04 : 0),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isPlayable)
        .opacity(isPlayable || chapter.status != .pending ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .help(chapter.lastError ?? (isPlayable ? "Play this chapter" : "Not converted yet"))
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
