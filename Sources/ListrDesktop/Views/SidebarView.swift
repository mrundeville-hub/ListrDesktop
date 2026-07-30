import SwiftUI

// One uniform "Library" card: header, book rows, import action.
struct SidebarView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore
    @Binding var selection: Book.ID?
    var onImport: () -> Void

    @State private var bookPendingRemoval: Book?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Library")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ListrTheme.ink)
                Spacer()
                ListrChip(
                    text: "listr",
                    icon: "waveform",
                    fill: ListrTheme.accentWash,
                    tint: ListrTheme.accent
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(libraryStore.books) { book in
                        BookRow(book: book, isSelected: selection == book.id) {
                            selection = book.id
                        }
                        .contextMenu {
                            Button("Remove from library…", role: .destructive) {
                                bookPendingRemoval = book
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Button {
                    onImport()
                } label: {
                    Label(libraryStore.isImporting ? "Importing…" : "Import book", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ListrPillButtonStyle())
                .disabled(libraryStore.isImporting)

                Text("FB2 · EPUB · TXT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ListrTheme.mutedLabel)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxHeight: .infinity)
        .listrCard()
        .confirmationDialog(
            "Remove “\(bookPendingRemoval?.title ?? "")” from the library?",
            isPresented: Binding(
                get: { bookPendingRemoval != nil },
                set: { if !$0 { bookPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let book = bookPendingRemoval else { return }
                if playbackStore.currentBookID == book.id {
                    playbackStore.unload()
                }
                libraryStore.removeBook(id: book.id)
                bookPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { bookPendingRemoval = nil }
        } message: {
            Text("Generated audio for this book is deleted. The imported file on disk is left alone.")
        }
    }
}

private struct BookRow: View {
    let book: Book
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconFill)
                        .frame(width: 38, height: 38)
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconTint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ListrTheme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ListrTheme.mutedLabel)
                        .lineLimit(1)

                    if book.progress > 0, book.progress < 1 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ListrTheme.chip)
                                Capsule()
                                    .fill(ListrTheme.accent)
                                    .frame(width: geo.size.width * book.progress)
                            }
                        }
                        .frame(height: 3)
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? ListrTheme.chip : .clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // Author plus whichever detail is useful right now: length once ready, share converted while working.
    private var subtitle: String {
        if book.status == .ready, book.duration > 0 {
            return "\(book.author) · \(book.durationLabel)"
        }
        if book.progress > 0, book.progress < 1 {
            return "\(statusLabel) · \(Int(book.progress * 100))%"
        }
        return "\(book.author) · \(statusLabel)"
    }

    private var statusLabel: String {
        switch book.status {
        case .ready: "Ready"
        case .converting: "Converting"
        case .failed: "Failed"
        case .queued: "Queued"
        case .imported: "Imported"
        }
    }

    private var iconName: String {
        switch book.status {
        case .ready: "checkmark"
        case .converting: "waveform"
        case .failed: "exclamationmark.triangle.fill"
        case .queued: "clock"
        case .imported: "book.closed.fill"
        }
    }

    private var iconFill: Color {
        switch book.status {
        case .failed: Color.red.opacity(0.1)
        case .converting: ListrTheme.accentWash
        default: isSelected ? ListrTheme.card : ListrTheme.chip
        }
    }

    private var iconTint: Color {
        switch book.status {
        case .failed: .red
        case .converting: ListrTheme.accent
        default: ListrTheme.ink
        }
    }
}
