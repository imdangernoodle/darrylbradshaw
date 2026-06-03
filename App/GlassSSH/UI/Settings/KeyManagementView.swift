import SwiftUI
import GlassSSHCore

/// Lists Secure Enclave–backed SSH keys, lets the user mint a new one, reveal and
/// copy the OpenSSH public key for pasting into `~/.ssh/authorized_keys`, and
/// delete keys. Private material never leaves the enclave; this view only ever
/// touches `ManagedKey` metadata via `CredentialManaging`.
struct KeyManagementView: View {
    let credentials: any CredentialManaging

    /// Local mirror of `credentials.keys` so the list animates on mutation; we
    /// re-sync from the source of truth after every operation.
    @State private var keys: [ManagedKey] = []
    @State private var isGenerating = false
    @State private var newKeyLabel = ""
    @State private var error: ErrorMessage?

    var body: some View {
        ZStack {
            GlassBackground()
            content
        }
        .navigationTitle("SSH Keys")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newKeyLabel = ""
                    isGenerating = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isGenerating) {
            generateSheet
        }
        .alert(item: $error) { message in
            Alert(title: Text("Key Error"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private var content: some View {
        if keys.isEmpty {
            ContentUnavailableView {
                Label("No Keys", systemImage: "key.slash")
            } description: {
                Text("Generate a Secure Enclave key, then add its public key to the server's authorized_keys.")
            } actions: {
                Button("Generate Key") {
                    newKeyLabel = ""
                    isGenerating = true
                }
                .buttonStyle(.glassAction)
            }
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(keys) { key in
                        KeyRow(key: key) { delete(key) }
                    }
                }
                .padding(20)
            }
        }
    }

    private var generateSheet: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                VStack(alignment: .leading, spacing: 18) {
                    Text("A new key pair will be created in the Secure Enclave. The private key can never be exported.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Label")
                            .font(.headline)
                        TextField("e.g. iPad — work", text: $newKeyLabel)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 22)
                    Spacer()
                    Button("Generate Key", action: generate)
                        .buttonStyle(.glassAction)
                        .frame(maxWidth: .infinity)
                        .disabled(newKeyLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("New Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isGenerating = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func reload() {
        keys = credentials.keys.sorted { $0.createdAt > $1.createdAt }
    }

    private func generate() {
        let label = newKeyLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        do {
            _ = try credentials.generateKey(label: label)
            isGenerating = false
            reload()
        } catch {
            self.error = ErrorMessage(text: error.localizedDescription)
        }
    }

    private func delete(_ key: ManagedKey) {
        do {
            try credentials.deleteKey(reference: key.id)
            reload()
        } catch {
            self.error = ErrorMessage(text: error.localizedDescription)
        }
    }
}

/// A single key card: label, fingerprint-style id, creation date, and actions to
/// copy the OpenSSH public key or delete the key.
private struct KeyRow: View {
    let key: ManagedKey
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .foregroundStyle(GlassPalette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.label)
                        .font(.headline)
                    Text(key.createdAt, format: .dateTime.year().month().day())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button {
                        withAnimation { isExpanded.toggle() }
                    } label: {
                        Label(isExpanded ? "Hide Public Key" : "Show Public Key",
                              systemImage: "eye")
                    }
                    Button(action: copy) {
                        Label("Copy Public Key", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Key", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(key.openSSHPublicKey)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    Button(action: copy) {
                        Label(didCopy ? "Copied" : "Copy for authorized_keys",
                              systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.glassAction)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }

    private func copy() {
        UIPasteboard.general.string = key.openSSHPublicKey
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { didCopy = false }
        }
    }
}

/// Identifiable wrapper so a thrown error can drive an `.alert(item:)`.
struct ErrorMessage: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Preview

#Preview {
    NavigationStack {
        KeyManagementView(credentials: PreviewCredentialStore.populated())
    }
}
