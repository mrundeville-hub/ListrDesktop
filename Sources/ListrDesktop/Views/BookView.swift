import SwiftUI

// One open book: the text being read in the middle, chapters in the inspector on the right.
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
        reader
            // Explicit zero minimum: the hero's height grows as its text wraps, and a minimum
            // size that depends on width sends the split view (with the inspector open) into an
            // endless constraint loop that AppKit ends with a crash.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .listrPlayerBar(book)
            .animation(.smooth(duration: 0.3), value: isReading)
            .navigationTitle(book.title)
            .navigationSubtitle(book.author)
            .toolbar { toolbar }
            .inspector(isPresented: $showsChapters) {
                ChapterList(book: book)
                    .inspectorColumnWidth(min: 240, ideal: 290, max: 420)
            }
            .background { CoverBackdrop(book: book) }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar) // the cover colors run up under it
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

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: onBack) {
                Label("Library", systemImage: "chevron.backward")
            }
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to the library")
        }

        ToolbarItem {
            conversionControl
        }

        ToolbarItem {
            Menu {
                Button("Regenerate Audio…") { isConfirmingRegenerate = true }
                    .disabled(!libraryStore.canRegenerateSelectedBook)
                Divider()
                Button("Remove from Library…", role: .destructive, action: onRemove)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More")
        }

        ToolbarItem {
            Button {
                showsChapters.toggle()
            } label: {
                Label("Chapters", systemImage: "sidebar.right")
            }
            .help(showsChapters ? "Hide chapters" : "Show chapters")
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
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Stop converting. Finished chapters are kept.")
            }
            .padding(.horizontal, 6)
            .animation(.snappy, value: readyCount)
        } else if libraryStore.conversionQueue.contains(book.id) {
            Text("Waiting to convert")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ListrTheme.mutedLabel)
                .padding(.horizontal, 6)
                .help("Starts when the books ahead of it in the queue are done")
        } else if libraryStore.canConvertSelectedBook, book.resumeChapter != nil {
            Button("Convert the Rest", action: convert)
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
            PagedReader(fontSize: 21)
                .transition(.opacity)
        } else {
            hero
                .transition(.opacity)
        }
    }

    // Before anything plays: the book itself and the single next step.
    private var hero: some View {
        VStack(spacing: 24) {
            ListrCover(seed: book.title, imagePath: book.coverPath, cornerRadius: 8)
                .frame(width: 168, height: 224)
                .shadow(color: .black.opacity(0.25), radius: 28, y: 14)

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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else if libraryStore.isConvertingSelectedBook {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                hint("Converting the first chapter. You can start listening as soon as it is ready.")
            }
        } else if libraryStore.canConvertSelectedBook {
            VStack(spacing: 12) {
                Button("Convert to Audio", action: convert)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
            hint("Waiting in the queue. It starts when the books ahead of it are done.")
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
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(PlaybackStore.self) private var playbackStore

    let book: Book

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(book.chapters) { chapter in
                    ChapterRow(chapter: chapter, isActive: activeChapterID == chapter.id, isPlaying: playbackStore.isPlaying)
                        .tag(chapter.id)
                        .selectionDisabled(!chapter.isReady)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } header: {
                HStack {
                    Text("Chapters")
                    Spacer()
                    Text(summary)
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden) // the cover-colored backdrop shows through
    }

    private var activeChapterID: Chapter.ID? {
        playbackStore.currentBookID == book.id ? playbackStore.currentChapterID : nil
    }

    // Selecting a chapter plays it; the playing one stays selected.
    private var selection: Binding<Chapter.ID?> {
        Binding(
            get: { activeChapterID },
            set: { id in
                guard let id, id != activeChapterID, let chapter = book.chapters.first(where: { $0.id == id }) else { return }
                playbackStore.play(bookID: book.id, chapter: chapter, speed: conversionStore.speed)
            }
        )
    }

    private var summary: String {
        let total = book.chapters.count
        let ready = Int((book.progress * Double(total)).rounded())
        return ready == total ? "\(total)" : "\(ready) of \(total) ready"
    }
}

private struct ChapterRow: View {
    let chapter: Chapter
    let isActive: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isActive {
                    // ponytail: still, not animated: a looping symbol effect redraws the window every frame.
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                } else {
                    Text("\(chapter.index)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)

                if let lastError = chapter.lastError {
                    Text(lastError)
                        .font(.caption)
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
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .opacity(chapter.status == .pending ? 0.45 : 1)
        .help(chapter.lastError ?? (chapter.isReady ? "Play this chapter" : "Not converted yet"))
    }
}

// The book's own colors behind the whole screen, as Music does behind an album: the cover,
// blown up and blurred until only its colors remain, under a veil that keeps text readable.
private struct CoverBackdrop: View {
    let book: Book

    var body: some View {
        ListrCover(seed: book.title, imagePath: book.coverPath, cornerRadius: 0)
            .scaleEffect(1.3)
            .blur(radius: 80, opaque: true)
            .drawingGroup() // one static texture, not a live blur under the moving text
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            .ignoresSafeArea() // under the toolbar and the glass sidebar too
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
