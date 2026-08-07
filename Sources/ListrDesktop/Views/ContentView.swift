import SwiftUI

struct ContentView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackStore.self) private var playbackStore
    @State private var isImporterPresented = false

    var body: some View {
        @Bindable var libraryStore = libraryStore

        ZStack {
            ListrTheme.paper.ignoresSafeArea()

            GeometryReader { geo in
                HStack(alignment: .top, spacing: 20) {
                    SidebarView(selection: $libraryStore.selectedBookID) {
                        isImporterPresented = true
                    }
                    .frame(width: ListrAdaptiveLayout.sidebarWidth(forAvailableWidth: geo.size.width))

                    DetailView(book: libraryStore.selectedBook)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 30) // just clears the traffic lights, which end around y=26
                .padding(.bottom, 20)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .tint(ListrTheme.ink)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: BookFormat.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await libraryStore.importBook(from: url)
                }
            case .failure(let error):
                libraryStore.importError = error.localizedDescription
            }
        }
        .alert("Import failed", isPresented: Binding(
            get: { libraryStore.importError != nil },
            set: { if !$0 { libraryStore.importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(libraryStore.importError ?? "Unknown import error")
        }
        .alert("Conversion failed", isPresented: Binding(
            get: { libraryStore.conversionError != nil },
            set: { if !$0 { libraryStore.conversionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(libraryStore.conversionError ?? "Unknown conversion error")
        }
        .alert("Playback failed", isPresented: Binding(
            get: { playbackStore.playbackError != nil },
            set: { if !$0 { playbackStore.playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackStore.playbackError ?? "Unknown playback error")
        }
        .alert("Library storage failed", isPresented: Binding(
            get: { libraryStore.persistenceError != nil },
            set: { if !$0 { libraryStore.persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(libraryStore.persistenceError ?? "Unknown storage error")
        }
        .task {
            await libraryStore.loadPersistedLibraryIfNeeded()
        }
    }
}
