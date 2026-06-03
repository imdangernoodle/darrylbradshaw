import SwiftUI
import GlassSSHCore

/// Add or edit a `ConnectionProfile`. Captures name, host, port, username, and
/// the authentication method, with optional key selection when authenticating by
/// public key. Validation mirrors `ConnectionProfile.isValid`; the Save button is
/// disabled until the edited profile is valid.
///
/// Secrets (passwords / private key material) are never handled here — only the
/// `keyReference` metadata is chosen. The caller persists the returned profile.
struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss

    /// Working copy of the profile being edited (or a freshly seeded one).
    @State private var draft: ConnectionProfile
    /// Bound to the port `TextField` as text so we can validate numeric entry.
    @State private var portText: String

    private let isEditing: Bool
    private let credentials: (any CredentialManaging)?
    private let onSave: (ConnectionProfile) -> Void

    /// Edit an existing saved profile. The caller persists the result via update.
    init(
        editing profile: ConnectionProfile,
        credentials: (any CredentialManaging)? = nil,
        onSave: @escaping (ConnectionProfile) -> Void
    ) {
        self.init(seed: profile, isEditing: true, credentials: credentials, onSave: onSave)
    }

    /// Create a new connection, optionally pre-filled (e.g. from a discovered
    /// host). The caller persists the result via add.
    init(
        seed: ConnectionProfile = ConnectionProfile(name: "", host: "", username: ""),
        credentials: (any CredentialManaging)? = nil,
        onSave: @escaping (ConnectionProfile) -> Void
    ) {
        self.init(seed: seed, isEditing: false, credentials: credentials, onSave: onSave)
    }

    private init(
        seed: ConnectionProfile,
        isEditing: Bool,
        credentials: (any CredentialManaging)?,
        onSave: @escaping (ConnectionProfile) -> Void
    ) {
        self._draft = State(initialValue: seed)
        self._portText = State(initialValue: String(seed.port))
        self.isEditing = isEditing
        self.credentials = credentials
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                authSection
            }
            .scrollContentBackground(.hidden)
            .background { GlassBackground() }
            .navigationTitle(isEditing ? "Edit Connection" : "New Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(GlassActionButtonStyle())
                        .disabled(!isSaveEnabled)
                }
            }
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $draft.name)
                .textInputAutocapitalization(.words)

            TextField("Host", text: $draft.host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            TextField("Port", text: $portText)
                .keyboardType(.numberPad)
                .onChange(of: portText) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { portText = digits }
                    draft.port = Int(digits) ?? 0
                }

            TextField("Username", text: $draft.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .listRowBackground(glassRowBackground)
    }

    @ViewBuilder
    private var authSection: some View {
        Section("Authentication") {
            Picker("Method", selection: $draft.authMethod) {
                Text("Password").tag(ConnectionProfile.AuthMethod.password)
                Text("Public Key").tag(ConnectionProfile.AuthMethod.publicKey)
            }
            .pickerStyle(.segmented)

            if draft.authMethod == .publicKey {
                keySelector
            }
        }
        .listRowBackground(glassRowBackground)
    }

    @ViewBuilder
    private var keySelector: some View {
        let keys = credentials?.keys ?? []
        if keys.isEmpty {
            Label("No keys available", systemImage: "key.slash")
                .foregroundStyle(GlassPalette.warning)
        } else {
            Picker("Key", selection: keyBinding) {
                Text("None").tag(String?.none)
                ForEach(keys) { key in
                    Text(key.label).tag(Optional(key.id))
                }
            }
        }
    }

    private var glassRowBackground: some View {
        Color.clear.glassCard(cornerRadius: 12)
    }

    // MARK: - State

    private var keyBinding: Binding<String?> {
        Binding(
            get: { draft.keyReference },
            set: { draft.keyReference = $0 }
        )
    }

    /// Save is enabled only when the underlying profile is valid and, for
    /// public-key auth, a key has been chosen.
    private var isSaveEnabled: Bool {
        guard draft.isValid else { return false }
        if draft.authMethod == .publicKey {
            return draft.keyReference?.isEmpty == false
        }
        return true
    }

    // MARK: - Actions

    private func save() {
        var profile = draft
        profile.name = profile.name.trimmingCharacters(in: .whitespaces)
        profile.host = profile.host.trimmingCharacters(in: .whitespaces)
        profile.username = profile.username.trimmingCharacters(in: .whitespaces)
        if profile.name.isEmpty { profile.name = profile.displayDestination }
        if profile.authMethod == .password { profile.keyReference = nil }
        onSave(profile)
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private final class PreviewCredentials: CredentialManaging, ObservableObject {
    var keys: [ManagedKey]
    init(_ keys: [ManagedKey]) { self.keys = keys }
    func generateKey(label: String) throws -> ManagedKey {
        ManagedKey(id: UUID().uuidString, label: label, openSSHPublicKey: "", createdAt: Date())
    }
    func deleteKey(reference: String) throws {}
    func savePassword(_ password: String, for profileID: UUID) throws {}
    func password(for profileID: UUID) -> String? { nil }
}

#Preview("New") {
    ConnectionFormView(
        credentials: PreviewCredentials([
            ManagedKey(id: "ed25519-main", label: "ed25519 (main)", openSSHPublicKey: "", createdAt: Date())
        ])
    ) { _ in }
}

#Preview("Edit") {
    ConnectionFormView(
        editing: ConnectionProfile(name: "Prod", host: "prod.example.com", port: 2222,
                                   username: "deploy", authMethod: .publicKey, keyReference: "ed25519-main"),
        credentials: PreviewCredentials([
            ManagedKey(id: "ed25519-main", label: "ed25519 (main)", openSSHPublicKey: "", createdAt: Date())
        ])
    ) { _ in }
}
#endif
