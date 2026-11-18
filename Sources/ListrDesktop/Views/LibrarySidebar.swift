import SwiftUI

enum SidebarItem: Hashable {
    case library
    case book(Book.ID)
}

// The sidebar: the whole library, then every book you have started, most recent first.
struct LibrarySidebar: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore

    @Binding var selection: SidebarItem?
    let onRemove: (Book) -> Void

    var body: some View {
        let started = libraryStore.startedBooks

        List(selection: $selection) {
            Section("Library") {
                Label("All Books", systemImage: "books.vertical")
                    .badge(libraryStore.books.count)
                    .tag(SidebarItem.library)
            }

            if !started.isEmpty {
                Section("Continue Listening") {
                    ForEach(started) { book in
                        SidebarBookRow(
                            book: book,
                            isPlaying: playbackStore.isPlaying && playbackStore.currentBookID == book.id
                        )
                        .tag(SidebarItem.book(book.id))
                        .contextMenu {
                            Button("Remove from Library…", role: .destructive) { onRemove(book) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarBookRow: View {
    let book: Book
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 10) {
            ListrCover(seed: book.title, imagePath: book.coverPath, cornerRadius: 3)
                .frame(width: 24, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(book.title)
                    .lineLimit(1)
                Text(position)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Playing")
            }
        }
        .padding(.vertical, 2)
        .help("\(book.title), \(book.author)")
    }

    private var position: String {
        let index = book.chapters.lastIndex { ($0.resumePosition ?? 0) > 0 } ?? 0
        return "Chapter \(index + 1) of \(book.chapters.count)"
    }
}

extension LibraryStore {
    /// Books listened to at least once, the most recent first.
    var startedBooks: [Book] {
        books
            .filter { $0.lastPlayedAt != nil || $0.chapters.contains { ($0.resumePosition ?? 0) > 0 } }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }
}
