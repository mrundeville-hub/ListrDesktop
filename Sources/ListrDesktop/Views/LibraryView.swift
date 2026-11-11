import SwiftUI

// Home screen: every book as a cover. Click to open, "+" or drop a file to add.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore

    let onOpen: (Book) -> Void
    let onImport: () -> Void
    let onRemove: (Book) -> Void

    @State private var query = ""
    @AppStorage("library.sort") private var sort = Sort.recent
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ListrTopBar(title: "Library") {
                EmptyView()
            } trailing: {
                if !libraryStore.books.isEmpty {
                    searchField
                    sortMenu
                }

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(ListrIconButtonStyle())
                .help("Voice settings")

                Button(action: onImport) {
                    Image(systemName: "plus")
                }
                .buttonStyle(ListrIconButtonStyle(kind: .filled))
                .disabled(libraryStore.isImporting)
                .help("Add a book")
            }

            if libraryStore.books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    ListeningSummary()
                        .padding(.horizontal, 44)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 32, alignment: .top)],
                        alignment: .leading,
                        spacing: 36
                    ) {
                        ForEach(visibleBooks) { book in
                            BookCell(book: book, isPlaying: isPlaying(book)) {
                                onOpen(book)
                            }
                            .contextMenu {
                                Button("Remove from Library…", role: .destructive) { onRemove(book) }
                            }
                        }
                    }
                    .padding(.horizontal, 44)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    .animation(.smooth(duration: 0.25), value: visibleBooks.map(\.id))

                    if visibleBooks.isEmpty {
                        Text("No books match “\(query)”")
                            .font(.system(size: 14))
                            .foregroundStyle(ListrTheme.mutedLabel)
                            .padding(.top, 40)
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let playingBook {
                PlayerBar(book: playingBook) { onOpen(playingBook) }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: playingBook?.id)
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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ListrTheme.mutedLabel)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onExitCommand {
                    query = ""
                    isSearchFocused = false
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ListrTheme.mutedLabel)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(width: 190, height: 30)
        .background(ListrTheme.fill, in: Capsule())
        .background {
            // ⌘F jumps to the search field.
            Button("Search") { isSearchFocused = true }
                .keyboardShortcut("f")
                .hidden()
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ListrTheme.ink)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort books")
    }

    private var playingBook: Book? {
        libraryStore.books.first { $0.id == playbackStore.currentBookID }
    }

    private func isPlaying(_ book: Book) -> Bool {
        playbackStore.currentBookID == book.id && playbackStore.isPlaying
    }

    // An empty shelf: dots where the covers will be.
    private var emptyState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 34) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 46) {
                        ForEach(0..<5, id: \.self) { _ in
                            Circle()
                                .fill(ListrTheme.ink.opacity(0.18))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("No books yet")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ListrTheme.ink)
                Text("Drop an FB2, EPUB or TXT file here and Listr turns it into an audiobook.")
                    .font(.system(size: 14))
                    .foregroundStyle(ListrTheme.mutedLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button("Add a book", action: onImport)
                .buttonStyle(ListrCapsuleButtonStyle(prominent: true, large: true))
                .disabled(libraryStore.isImporting)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BookCell: View {
    let book: Book
    let isPlaying: Bool
    let open: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                ListrCover(seed: book.title)
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
        switch book.status {
        case .ready: book.duration > 0 ? book.durationLabel : ""
        case .converting: "Converting, \(Int(book.progress * 100))%"
        case .failed: "Needs attention"
        case .queued: "\(Int(book.progress * 100))% converted"
        case .imported: "Not converted yet"
        }
    }

    @ViewBuilder private var badge: some View {
        if isPlaying {
            badgeIcon("waveform")
                .symbolEffect(.variableColor.iterative, isActive: true)
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
