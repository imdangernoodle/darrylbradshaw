import SwiftUI

/// Horizontal strip of open-document tabs above the editor.
struct TabBarView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(store.openDocuments) { doc in
                    TabItem(document: doc)
                }
            }
        }
        .frame(height: 40)
        .background(store.theme.chrome)
    }
}

private struct TabItem: View {
    @EnvironmentObject var store: WorkspaceStore
    @ObservedObject var document: EditorDocument

    private var isActive: Bool { store.activeDocumentID == document.id }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: document.language.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(store.theme.dim)

            Text(document.name)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? store.theme.foregroundColor : store.theme.dim)
                .lineLimit(1)

            Button {
                store.close(document)
            } label: {
                Image(systemName: document.isDirty ? "circle.fill" : "xmark")
                    .font(.system(size: document.isDirty ? 8 : 11))
                    .foregroundStyle(store.theme.dim)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(isActive ? store.theme.swiftBackground : store.theme.chrome)
        .overlay(alignment: .trailing) {
            Rectangle().fill(store.theme.chromeBar).frame(width: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.activate(document) }
    }
}
