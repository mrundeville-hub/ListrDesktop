import SwiftUI

struct ContentView: View {
    @Environment(LibraryStore.self) private var libraryStore
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

                Button {} label: {
                    Label("Convert", systemImage: "waveform")
                }
                .disabled(libraryStore.selectedBook == nil)
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
                Task { await libraryStore.importBook(from: url) }
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
    }
}
