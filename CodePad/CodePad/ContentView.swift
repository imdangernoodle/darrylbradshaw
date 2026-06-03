import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        HStack(spacing: 0) {
            ActivityBarView()

            if store.sidebarVisible {
                SidebarView()
                    .frame(width: 260)
                    .transition(.move(edge: .leading))
                Divider().overlay(store.theme.chromeBar)
            }

            VStack(spacing: 0) {
                if !store.openDocuments.isEmpty {
                    TabBarView()
                    Divider().overlay(store.theme.chromeBar)
                }

                if let doc = store.activeDocument {
                    CodeEditorView(document: doc, theme: store.theme)
                        .id(doc.id)
                        .ignoresSafeArea(.container, edges: .bottom)
                } else {
                    WelcomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(store.theme.swiftBackground)
        }
        .animation(.easeInOut(duration: 0.2), value: store.sidebarVisible)
        .preferredColorScheme(store.theme == .dark ? .dark : .light)
        .sheet(isPresented: $store.showCommandPalette) {
            CommandPaletteView()
                .environmentObject(store)
        }
        .fileImporter(
            isPresented: $store.importFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { store.handleOpenFiles($0) }
        .fileImporter(
            isPresented: $store.importFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            store.handleOpenFolder(result.map { $0.first ?? URL(fileURLWithPath: "/") })
        }
    }
}
