import SwiftUI

/// File-explorer sidebar showing the open folder as an expandable tree.
struct SidebarView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EXPLORER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(store.theme.dim)
                Spacer()
                Button { store.createNewFile() } label: {
                    Image(systemName: "doc.badge.plus")
                }
                Button { store.importFolder = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(store.theme.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(store.theme.chromeBar)

            if store.fileTree.isEmpty {
                emptyState
            } else {
                List {
                    OutlineGroup(store.fileTree, children: \.children) { node in
                        row(for: node)
                    }
                    .listRowBackground(store.theme.chrome)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 34)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(store.theme.chrome)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No folder opened")
                .font(.footnote)
                .foregroundStyle(store.theme.dim)
            Button("Open Folder") { store.importFolder = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func row(for node: FileNode) -> some View {
        if node.isDirectory {
            Label(node.name, systemImage: "folder")
                .foregroundStyle(store.theme.foregroundColor)
                .lineLimit(1)
        } else {
            Button {
                store.open(node.url)
            } label: {
                Label(node.name, systemImage: Language.detect(from: node.url).symbolName)
                    .foregroundStyle(isActive(node) ? store.theme.accent : store.theme.foregroundColor)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
    }

    private func isActive(_ node: FileNode) -> Bool {
        store.activeDocument?.url == node.url
    }
}
