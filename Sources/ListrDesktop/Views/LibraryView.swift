import SwiftUI

// Home screen: every book as a cover, in a grid or in Cover Flow. Click to open, "+" or drop a file to add.
struct LibraryView: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore

    let onOpen: (Book) -> Void
    let onImport: () -> Void
    let onRemove: (Book) -> Void

    @State private var query = ""
    @AppStorage("library.sort") private var sort = Sort.recent
    @AppStorage("library.layout") private var layout = Layout.grid
    @FocusState private var isSearchFocused: Bool
    @State private var isConfirmingConvertAll = false

    private enum Layout: String {
        case grid, coverFlow
    }

    var body: some View {
        content
            .navigationTitle("Library")
            .navigationSubtitle(libraryStore.books.isEmpty ? "" : visibleBooks.count == 1 ? "1 book" : "\(visibleBooks.count) books")
            .searchable(text: $query, placement: .toolbar, prompt: "Title or author")
            .searchFocused($isSearchFocused)
            .background {
                // ⌘F jumps to the search field.
                Button("Search") { isSearchFocused = true }
                    .keyboardShortcut("f")
                    .opacity(0) // not .hidden(): a hidden button does not receive its shortcut
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .toolbar { toolbar }
            .confirmationDialog(
                "Convert \(convertibleBooks.count) books to audio?",
                isPresented: $isConfirmingConvertAll,
                titleVisibility: .visible
            ) {
                Button("Convert") { convert(convertibleBooks) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They are converted one after another with the voice chosen in Settings. You can listen to finished chapters meanwhile, and stop at any time.")
            }
    }

    @ViewBuilder private var content: some View {
        if libraryStore.books.isEmpty {
            emptyState
        } else if visibleBooks.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if layout == .coverFlow {
            CoverFlowView(books: visibleBooks, onOpen: onOpen)
        } else {
            grid
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if !libraryStore.books.isEmpty {
            ToolbarItem {
                Picker("View", selection: $layout) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(Layout.grid)
                    Label("Cover Flow", systemImage: "rectangle.stack").tag(Layout.coverFlow)
                }
                .pickerStyle(.segmented)
                .help("Show the books as a grid or in Cover Flow")
            }

            ToolbarItem {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort books")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: onImport) {
                Label("Add Book", systemImage: "plus")
            }
            .disabled(libraryStore.isImporting)
            .help("Add a book")
        }
    }

    private var grid: some View {
        ScrollView {
            ListeningSummary()
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 8)

            shelfStatus
                .padding(.horizontal, 28)
                .padding(.top, 8)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 28, alignment: .top)],
                alignment: .leading,
                spacing: 32
            ) {
                ForEach(visibleBooks) { book in
                    BookCell(
                        book: book,
                        isPlaying: isPlaying(book),
                        isQueued: libraryStore.conversionQueue.contains(book.id)
                    ) {
                        onOpen(book)
                    }
                    .contextMenu {
                        Button("Convert to Audio") { convert([book]) }
                            .disabled(!libraryStore.canConvert(book))
                        Divider()
                        Button("Remove from Library…", role: .destructive) { onRemove(book) }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .animation(.smooth(duration: 0.25), value: visibleBooks.map(\.id))
        }
    }

    // MARK: Conversion queue

    private var convertibleBooks: [Book] {
        visibleBooks.filter(libraryStore.canConvert)
    }

    private func convert(_ books: [Book]) {
        libraryStore.convert(bookIDs: books.map(\.id), configuration: conversionStore.activeConfiguration)
    }

    // One line between the summary and the shelf: how many books, and the conversion queue.
    private var shelfStatus: some View {
        HStack(spacing: 10) {
            Spacer()

            if let converting = libraryStore.books.first(where: { $0.id == libraryStore.convertingBookID }) {
                HStack(spacing: 8) {
                    ProgressView(value: converting.progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                    Text(queueLabel(converting))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(ListrTheme.ink)
                        .lineLimit(1)
                    Button {
                        libraryStore.cancelConversion()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Stop converting and clear the queue. Finished chapters are kept.")
                }
            }

            if !convertibleBooks.isEmpty {
                Button(convertibleBooks.count == 1 ? "Convert 1 book" : "Convert \(convertibleBooks.count) books") {
                    if convertibleBooks.count == 1 { convert(convertibleBooks) } else { isConfirmingConvertAll = true }
                }
                .buttonStyle(.bordered)
                .help("Add every book shown here to the conversion queue")
            }
        }
        .frame(minHeight: 24)
    }

    private func queueLabel(_ converting: Book) -> String {
        let waiting = libraryStore.conversionQueue.count
        let title = converting.title.count > 28 ? converting.title.prefix(27) + "…" : converting.title
        return "Converting “\(title)”" + (waiting > 0 ? ", \(waiting) waiting" : "")
    }

    // MARK: Search and sort

    private enum Sort: String, CaseIterable {
        case recent = "Recently added"
        case title = "Title"
        case author = "Author"
    }

    private var visibleBooks: [Book] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let found = text.isEmpty ? libraryStore.books : libraryStore.books.filter {
            $0.title.localizedStandardContains(text) || $0.author.localizedStandardContains(text)
        }
        func ascending(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
        switch sort {
        case .recent: return found // the library keeps the newest book first
        case .title: return found.sorted { ascending($0.title, $1.title) }
        case .author: return found.sorted { $0.author == $1.author ? ascending($0.title, $1.title) : ascending($0.author, $1.author) }
        }
    }

    private func isPlaying(_ book: Book) -> Bool {
        playbackStore.currentBookID == book.id && playbackStore.isPlaying
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Books Yet", systemImage: "books.vertical")
        } description: {
            Text("Drop an FB2, EPUB or TXT file here and Listr turns it into an audiobook.")
        } actions: {
            Button("Add a Book…", action: onImport)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(libraryStore.isImporting)
        }
    }
}

private struct BookCell: View {
    let book: Book
    let isPlaying: Bool
    let isQueued: Bool
    let open: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                ListrCover(seed: book.title, imagePath: book.coverPath)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) { badge.padding(10) }
                    .shadow(color: .black.opacity(isHovered ? 0.16 : 0.08), radius: isHovered ? 18 : 10, y: isHovered ? 10 : 5)
                    .scaleEffect(isHovered ? 1.03 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ListrTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(book.author)
                        .font(.system(size: 12))
                        .foregroundStyle(ListrTheme.mutedLabel)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(ListrTheme.mutedLabel.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.25), value: isHovered)
        .accessibilityLabel("\(book.title), \(book.author), \(detail)")
    }

    // One quiet line: what you can do with this book right now.
    private var detail: String {
        if isQueued { return "Waiting to convert" }
        return switch book.status {
        case .ready: book.duration > 0 ? book.durationLabel : ""
        case .converting: "Converting, \(Int(book.progress * 100))%"
        case .failed: "Needs attention"
        case .queued: "\(Int(book.progress * 100))% converted"
        case .imported: "Not converted yet"
        }
    }

    @ViewBuilder private var badge: some View {
        if isPlaying {
            badgeIcon("speaker.wave.2.fill") // still: a looping symbol effect redraws every frame
        } else if book.status == .failed {
            badgeIcon("exclamationmark")
        } else if book.status == .converting {
            ProgressView(value: book.progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: Circle())
        }
    }

    private func badgeIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ListrTheme.ink)
            .frame(width: 28, height: 28)
            .background(.regularMaterial, in: Circle())
    }
}
