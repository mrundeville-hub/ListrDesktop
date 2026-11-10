import SwiftUI

// Home screen: every book as a cover. Click to open, "+" or drop a file to add.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore

    let onOpen: (Book) -> Void
    let onImport: () -> Void
    let onRemove: (Book) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ListrTopBar(title: "Library") {
                EmptyView()
            } trailing: {
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
                        ForEach(libraryStore.books) { book in
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
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(ListrTheme.mutedLabel)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.25), value: isHovered)
        .accessibilityLabel("\(book.title), \(detail)")
    }

    // One quiet line: what you can do with this book right now.
    private var detail: String {
        switch book.status {
        case .ready: book.duration > 0 ? book.durationLabel : book.author
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
