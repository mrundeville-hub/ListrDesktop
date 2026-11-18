import SwiftUI

// Floating player: the text and the transport in a small always-on-top card.
struct PlaybackOverlayView: View {
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(OverlayStore.self) private var overlayStore
    @Environment(PlaybackStore.self) private var playbackStore

    var body: some View {
        VStack(spacing: 0) {
            header
            reader
            player
        }
        .frame(minWidth: 320, idealWidth: 400, maxWidth: 520, minHeight: 400, idealHeight: 640)
        .background(ListrTheme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
        .padding(24) // room for the soft shadow inside the transparent panel
    }

    private var header: some View {
        @Bindable var conversionStore = conversionStore

        return ZStack {
            Text(playbackStore.currentTitle.isEmpty ? "Nothing playing" : playbackStore.currentTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ListrTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, 96)
                .allowsHitTesting(false)

            HStack {
                Button {
                    overlayStore.isPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(ListrIconButtonStyle(size: 28))
                .help("Close and return to the main window")

                Spacer()

                ListrSleepMenu()
                ListrSpeedMenu(speed: $conversionStore.speed) { playbackStore.applySpeed($0) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(WindowDragHandle()) // grab the header to move the player
    }

    @ViewBuilder private var reader: some View {
        if playbackStore.currentText.isEmpty {
            Text("Close this window, open a book and press play. The text follows the voice here.")
                .font(.system(size: 15))
                .foregroundStyle(ListrTheme.mutedLabel)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            PagedReader(fontSize: 18, margin: 28)
        }
    }

    private var player: some View {
        VStack(spacing: 10) {
            PlayerProgress(isLoaded: playbackStore.hasLoadedChapter)

            if let currentBook {
                PlayerTransport(book: currentBook, playSize: 44)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }


    private var currentBook: Book? {
        libraryStore.books.first { $0.id == playbackStore.currentBookID }
    }
}

// Dragging this moves the window. SwiftUI content does not count as "window background"
// to AppKit, so isMovableByWindowBackground alone leaves the card stuck in place.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HandleView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
