import SwiftUI

struct ContentView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ConversionStore.self) private var conversionStore
    @Environment(PlaybackStore.self) private var playbackStore
    @State private var isImporterPresented = false

    var body: some View {
        @Bindable var libraryStore = libraryStore

        NavigationSplitView {
            SidebarView(selection: $libraryStore.selectedBookID)
        } detail: {
            DetailView(book: libraryStore.selectedBook)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .disabled(libraryStore.isImporting)

                if libraryStore.isConverting {
                    Button {
                        libraryStore.cancelConversion()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        libraryStore.convertSelectedBook(using: conversionStore.selectedEngine)
                    } label: {
                        Label("Convert", systemImage: "waveform")
                    }
                    .disabled(!libraryStore.canConvertSelectedBook)
                }
            }
        }
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
