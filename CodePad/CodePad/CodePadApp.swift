import SwiftUI

@main
struct CodePadApp: App {
    @StateObject private var store = WorkspaceStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .commands {
            // File menu (hardware keyboard shortcuts on iPad)
            CommandGroup(replacing: .newItem) {
                Button("New File") { store.createNewFile() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open File…") { store.importFile = true }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Open Folder…") { store.importFolder = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.saveActive() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Close Tab") { store.closeActive() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandMenu("View") {
                Button("Command Palette") { store.showCommandPalette = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Toggle Sidebar") { store.sidebarVisible.toggle() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Toggle Theme") { store.toggleTheme() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
