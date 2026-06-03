import SwiftUI
import GlassSSHCore

/// Root scaffold. The Connections UI unit replaces the sidebar contents and the
/// Terminal Screen unit provides the detail pane; this baseline simply compiles
/// and renders so the project is runnable before those units land.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List {
                Section("Saved") {
                    Text("No connections yet")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("GlassSSH")
        } detail: {
            ContentUnavailableView(
                "Select a connection",
                systemImage: "terminal",
                description: Text("Choose a host from the sidebar or scan a QR code to begin.")
            )
        }
        .sheet(item: $model.pendingImport) { profile in
            NavigationStack {
                Text("Import \(profile.displayDestination)")
                    .navigationTitle("Add Connection")
            }
        }
    }
}
