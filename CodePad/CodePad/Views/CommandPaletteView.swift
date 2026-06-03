import SwiftUI

/// VS Code–style command palette (⌘⇧P).
struct CommandPaletteView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [PaletteCommand] {
        let all = store.paletteCommands
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { command in
                Button {
                    command.action()
                    dismiss()
                } label: {
                    HStack {
                        Text(command.title)
                        Spacer()
                        if let shortcut = command.shortcut {
                            Text(shortcut)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Type a command")
            .navigationTitle("Command Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
