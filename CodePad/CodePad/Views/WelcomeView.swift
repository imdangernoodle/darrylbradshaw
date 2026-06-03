import SwiftUI

/// Landing screen shown when no document is open.
struct WelcomeView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(store.theme.accent)

            Text("CodePad")
                .font(.system(size: 34, weight: .thin))
                .foregroundStyle(store.theme.foregroundColor)

            Text("A VS Code–style editor for your iPad")
                .font(.subheadline)
                .foregroundStyle(store.theme.dim)

            VStack(alignment: .leading, spacing: 10) {
                actionRow("New File", "doc.badge.plus", "⌘N") { store.createNewFile() }
                actionRow("Open File…", "doc.text", "⌘O") { store.importFile = true }
                actionRow("Open Folder…", "folder", "⌘⇧O") { store.importFolder = true }
                actionRow("Command Palette", "command", "⌘⇧P") { store.showCommandPalette = true }
            }
            .padding(.top, 8)

            Text("Tip: pair a Bluetooth keyboard for full shortcuts, or use the symbol bar above the on-screen keyboard.")
                .font(.caption)
                .foregroundStyle(store.theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func actionRow(_ title: String, _ symbol: String, _ shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                    .foregroundStyle(store.theme.accent)
                Spacer()
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(store.theme.dim)
            }
            .frame(width: 320)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
