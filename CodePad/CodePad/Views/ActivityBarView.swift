import SwiftUI

/// The slim vertical bar of icons on the far left, à la VS Code.
struct ActivityBarView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 4) {
            actButton("doc.on.doc", active: store.sidebarVisible) {
                store.sidebarVisible.toggle()
            }
            actButton("magnifyingglass", active: false) {
                store.showCommandPalette = true
            }
            actButton("plus.square", active: false) {
                store.createNewFile()
            }
            actButton("folder.badge.plus", active: false) {
                store.importFolder = true
            }

            Spacer()

            actButton(store.theme == .dark ? "sun.max" : "moon", active: false) {
                store.toggleTheme()
            }
        }
        .padding(.vertical, 8)
        .frame(width: 50)
        .frame(maxHeight: .infinity)
        .background(store.theme.chromeBar)
    }

    private func actButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 46, height: 46)
                .foregroundStyle(active ? store.theme.foregroundColor : store.theme.dim)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(active ? store.theme.accent : .clear)
                        .frame(width: 2)
                }
        }
        .buttonStyle(.plain)
    }
}
