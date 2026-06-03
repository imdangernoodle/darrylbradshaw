import SwiftUI
import GlassSSHCore

/// Displays pinned host-key fingerprints from a `KnownHostsStore` and lets the
/// user forget entries (e.g. after decommissioning a server or to re-trigger
/// trust-on-first-use). Entry keys follow OpenSSH's `known_hosts` convention:
/// a bare host for the default port, or `[host]:port` otherwise.
struct KnownHostsView: View {
    let store: KnownHostsStore

    @State private var entries: [KnownHostEntry] = []
    @State private var pendingForget: KnownHostEntry?

    var body: some View {
        ZStack {
            GlassBackground()
            content
        }
        .navigationTitle("Known Hosts")
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: reload)
        .confirmationDialog(
            "Forget this host?",
            isPresented: forgetBinding,
            titleVisibility: .visible,
            presenting: pendingForget
        ) { entry in
            Button("Forget \(entry.displayHost)", role: .destructive) {
                forget(entry)
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("The next connection to \(entry.displayHost) will be treated as a first-time connection.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "No Known Hosts",
                systemImage: "checkmark.shield",
                description: Text("Host fingerprints you trust will appear here after your first connection.")
            )
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(entries) { entry in
                        KnownHostRow(entry: entry) {
                            pendingForget = entry
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var forgetBinding: Binding<Bool> {
        Binding(
            get: { pendingForget != nil },
            set: { if !$0 { pendingForget = nil } }
        )
    }

    private func reload() {
        entries = store.allEntries
            .map { KnownHostEntry(key: $0.key, fingerprint: $0.value) }
            .sorted { $0.displayHost.localizedCaseInsensitiveCompare($1.displayHost) == .orderedAscending }
    }

    private func forget(_ entry: KnownHostEntry) {
        store.forget(host: entry.host, port: entry.port)
        reload()
    }
}

/// A parsed `known_hosts` entry. Splits the canonical `[host]:port` / `host` key
/// back into a host and port so it can be passed to `KnownHostsStore.forget`.
struct KnownHostEntry: Identifiable, Hashable {
    let id: String
    let host: String
    let port: Int
    let fingerprint: String

    init(key: String, fingerprint: String) {
        self.id = key
        self.fingerprint = fingerprint
        if key.hasPrefix("["), let closing = key.range(of: "]:") {
            self.host = String(key[key.index(after: key.startIndex)..<closing.lowerBound])
            self.port = Int(key[closing.upperBound...]) ?? ConnectionProfile.defaultPort
        } else {
            self.host = key
            self.port = ConnectionProfile.defaultPort
        }
    }

    var displayHost: String {
        port == ConnectionProfile.defaultPort ? host : "\(host):\(port)"
    }
}

/// A single known-host card showing the destination and its pinned fingerprint.
private struct KnownHostRow: View {
    let entry: KnownHostEntry
    let onForget: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayHost)
                    .font(.headline)
                Text(entry.fingerprint)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(role: .destructive, action: onForget) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        KnownHostsView(store: PreviewKnownHosts.populated())
    }
}
