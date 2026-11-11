import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var overlayStore: OverlayStore?
    private weak var mainWindow: NSWindow?

    func present(
        overlayStore: OverlayStore,
        playbackStore: PlaybackStore,
        libraryStore: LibraryStore,
        conversionStore: ConversionStore
    ) {
        self.overlayStore = overlayStore
        collapseMainWindow()

        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let content = PlaybackOverlayView()
            .environment(overlayStore)
            .environment(playbackStore)
            .environment(libraryStore)
            .environment(conversionStore)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 448, height: 768),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Listr Reading Overlay"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // card draws its own soft shadow
        let hosting = NSHostingView(rootView: content)
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.minSize = NSSize(width: 368, height: 448)
        // Comes back where it was left; centred only the first time.
        if !panel.setFrameUsingName("ListrReadingOverlay") {
            panel.center()
        }
        panel.setFrameAutosaveName("ListrReadingOverlay")
        panel.standardWindowButton(.closeButton)?.isHidden = true // card has its own close
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        self.panel = panel
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        overlayStore?.isPresented = false
        restoreMainWindow()
    }

    // The fullscreen window "collapses" into the overlay: hidden while it floats.
    // ponytail: polls briefly because at launch the WindowGroup window appears after onAppear.
    private func collapseMainWindow(attempt: Int = 0) {
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) {
            mainWindow = window
            window.orderOut(nil)
            return
        }
        guard attempt < 10 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.overlayStore?.isPresented == true else { return }
            self.collapseMainWindow(attempt: attempt + 1)
        }
    }

    private func restoreMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow = nil
    }
}
