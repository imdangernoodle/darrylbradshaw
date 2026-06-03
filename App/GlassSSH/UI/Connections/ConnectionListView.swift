import Combine
import SwiftUI
import GlassSSHCore

/// The sidebar list of connections. Combines saved `ConnectionProfile`s with
/// live Bonjour-discovered hosts in two sections, and drives selection in the
/// surrounding `NavigationSplitView`.
///
/// Dependencies are protocol-typed (`ProfileStoring`, `HostDiscovering`) so this
/// view stays decoupled from the concrete store / discovery implementations
/// supplied by sibling work units.
struct ConnectionListView<Store: ProfileStoring, Discovery: HostDiscovering>: View {
    @ObservedObject private var store: StoreBox<Store>
    @ObservedObject private var discovery: DiscoveryBox<Discovery>

    /// The currently selected saved profile, owned by the split view.
    @Binding var selection: ConnectionProfile?

    /// Optional credential source so the add/edit form can offer key selection.
    private let credentials: (any CredentialManaging)?

    /// Drives the add sheet. Holds a blank profile (from the "+" button) or one
    /// pre-filled from a discovered host; saving always calls `store.add`.
    @State private var addDraft: ConnectionProfile?
    /// Drives the edit sheet for an existing saved profile; saving calls
    /// `store.update`.
    @State private var editingProfile: ConnectionProfile?

    init(
        store: Store,
        discovery: Discovery,
        selection: Binding<ConnectionProfile?>,
        credentials: (any CredentialManaging)? = nil
    ) {
        self.store = StoreBox(store)
        self.discovery = DiscoveryBox(discovery)
        self._selection = selection
        self.credentials = credentials
    }

    var body: some View {
        List(selection: $selection) {
            savedSection
            discoveredSection
        }
        .scrollContentBackground(.hidden)
        .background { GlassBackground() }
        .navigationTitle("GlassSSH")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addDraft = ConnectionProfile(name: "", host: "", username: "")
                } label: {
                    Label("Add Connection", systemImage: "plus")
                }
                .buttonStyle(GlassActionButtonStyle())
            }
        }
        .overlay {
            if store.value.profiles.isEmpty && discovery.value.discovered.isEmpty {
                emptyState
            }
        }
        .sheet(item: $addDraft) { draft in
            ConnectionFormView(seed: draft, credentials: credentials) { newProfile in
                store.value.add(newProfile)
                selection = newProfile
            }
        }
        .sheet(item: $editingProfile) { profile in
            ConnectionFormView(editing: profile, credentials: credentials) { updated in
                store.value.update(updated)
                if selection?.id == updated.id { selection = updated }
            }
        }
        .onAppear { discovery.value.start() }
        .onDisappear { discovery.value.stop() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var savedSection: some View {
        if !store.value.profiles.isEmpty {
            Section("Saved") {
                ForEach(store.value.profiles) { profile in
                    ConnectionRow(content: .profile(profile))
                        .tag(profile)
                        .contextMenu {
                            Button {
                                editingProfile = profile
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                delete(profile)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete(perform: deleteAt)
            }
        }
    }

    @ViewBuilder
    private var discoveredSection: some View {
        if !discovery.value.discovered.isEmpty {
            Section("On This Network") {
                ForEach(discovery.value.discovered) { host in
                    Button {
                        addFromDiscovered(host)
                    } label: {
                        ConnectionRow(content: .discovered(host))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Connections",
            systemImage: "terminal",
            description: Text("Tap + to add a host, or scan a QR code to import one.")
        )
    }

    // MARK: - Actions

    private func delete(_ profile: ConnectionProfile) {
        if selection?.id == profile.id { selection = nil }
        store.value.remove(profile)
    }

    private func deleteAt(_ offsets: IndexSet) {
        let targets = offsets.map { store.value.profiles[$0] }
        for profile in targets { delete(profile) }
    }

    /// Pre-fill a new profile from a discovered host so the user can confirm
    /// credentials before saving.
    private func addFromDiscovered(_ host: DiscoveredHost) {
        addDraft = ConnectionProfile(
            name: host.name,
            host: host.host ?? host.name,
            port: host.port ?? ConnectionProfile.defaultPort,
            username: ""
        )
    }
}

// MARK: - Observation bridges

/// Bridges a protocol-typed `ProfileStoring` (which may be an `ObservableObject`)
/// into a concrete `@ObservedObject` so SwiftUI re-renders on changes. The
/// generic constraint keeps this free of `AnyObject` erasure pitfalls.
private final class StoreBox<Store: ProfileStoring>: ObservableObject {
    let value: Store
    private var forwarder: AnyObject?

    init(_ value: Store) {
        self.value = value
        if let observable = value as? any ObservableObject {
            forwarder = Self.forward(observable, to: objectWillChange)
        }
    }

    private static func forward<O: ObservableObject>(
        _ observable: O,
        to subject: ObservableObjectPublisher
    ) -> AnyObject? {
        observable.objectWillChange.sink { _ in
            subject.send()
        } as AnyObject
    }
}

private final class DiscoveryBox<Discovery: HostDiscovering>: ObservableObject {
    let value: Discovery
    private var forwarder: AnyObject?

    init(_ value: Discovery) {
        self.value = value
        if let observable = value as? any ObservableObject {
            forwarder = Self.forward(observable, to: objectWillChange)
        }
    }

    private static func forward<O: ObservableObject>(
        _ observable: O,
        to subject: ObservableObjectPublisher
    ) -> AnyObject? {
        observable.objectWillChange.sink { _ in
            subject.send()
        } as AnyObject
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private final class PreviewProfileStore: ProfileStoring, ObservableObject {
    @Published private var items: [ConnectionProfile]
    var profiles: [ConnectionProfile] { items }

    init(_ items: [ConnectionProfile]) { self.items = items }

    func add(_ profile: ConnectionProfile) { items.append(profile) }
    func update(_ profile: ConnectionProfile) {
        if let i = items.firstIndex(where: { $0.id == profile.id }) { items[i] = profile }
    }
    func remove(_ profile: ConnectionProfile) { items.removeAll { $0.id == profile.id } }
    func reload() {}
}

@MainActor
private final class PreviewDiscovery: HostDiscovering, ObservableObject {
    @Published private var hosts: [DiscoveredHost]
    var discovered: [DiscoveredHost] { hosts }

    init(_ hosts: [DiscoveredHost]) { self.hosts = hosts }
    func start() {}
    func stop() {}
}

private struct ConnectionListPreview: View {
    @State private var selection: ConnectionProfile?
    private let store = PreviewProfileStore([
        ConnectionProfile(name: "Home Server", host: "192.168.1.20", username: "darryl"),
        ConnectionProfile(name: "Prod Box", host: "prod.example.com", port: 2222,
                          username: "deploy", authMethod: .publicKey, keyReference: "ed25519-main")
    ])
    private let discovery = PreviewDiscovery([
        DiscoveredHost(id: "1", name: "studio.local", host: "10.0.0.5", port: 22, kind: .ssh),
        DiscoveredHost(id: "2", name: "iPad Pairing", host: nil, port: nil, kind: .pairing)
    ])

    var body: some View {
        NavigationSplitView {
            ConnectionListView(store: store, discovery: discovery, selection: $selection)
        } detail: {
            Text(selection?.displayDestination ?? "Select a connection")
        }
    }
}

#Preview {
    ConnectionListPreview()
}
#endif
