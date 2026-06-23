import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Binding var selection: Book.ID?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(libraryStore.books) { book in
                    BookRow(book: book)
                        .tag(book.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Listr")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("local narration")
                    .font(.system(.caption, design: ListrTheme.mono).weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text("FB2 / EPUB / TXT")
                    .font(.system(.caption, design: ListrTheme.mono))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }
}

private struct BookRow: View {
    let book: Book

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(.body, design: ListrTheme.mono).weight(.semibold))
                    .lineLimit(1)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        switch book.status {
        case .ready: "checkmark.circle.fill"
        case .converting: "waveform.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .queued: "clock.fill"
        case .imported: "book.closed.fill"
        }
    }

    private var iconColor: Color {
        switch book.status {
        case .ready: ListrTheme.electricBlue
        case .converting: ListrTheme.citrusOrange
        case .failed: .red
        case .queued: .secondary
        case .imported: ListrTheme.ink
        }
    }
}
