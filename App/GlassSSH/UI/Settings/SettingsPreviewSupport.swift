import Foundation
import GlassSSHCore

/// Lightweight stand-ins used only by `#Preview` blocks in this folder. They live
/// behind `#if DEBUG` so they never ship in release builds. Production wiring
/// injects the real `CredentialManaging` / file-backed `KnownHostsStore`.
#if DEBUG

/// In-memory `CredentialManaging` for previews. `generateKey` synthesizes a fake
/// OpenSSH public key so the copy/reveal UI has realistic content.
@MainActor
final class PreviewCredentialStore: CredentialManaging {
    private(set) var keys: [ManagedKey]
    private var passwords: [UUID: String] = [:]

    init(keys: [ManagedKey] = []) {
        self.keys = keys
    }

    static func populated() -> PreviewCredentialStore {
        PreviewCredentialStore(keys: [
            ManagedKey(
                id: "se-tag-1",
                label: "iPad — work",
                openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyMaterialForPreviewOnly0001 iPad — work",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            ManagedKey(
                id: "se-tag-2",
                label: "Homelab",
                openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyMaterialForPreviewOnly0002 Homelab",
                createdAt: Date(timeIntervalSince1970: 1_710_000_000)
            )
        ])
    }

    func generateKey(label: String) throws -> ManagedKey {
        let tag = "se-tag-\(keys.count + 1)"
        let key = ManagedKey(
            id: tag,
            label: label,
            openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINewlyGeneratedPreviewKey\(keys.count) \(label)",
            createdAt: Date()
        )
        keys.append(key)
        return key
    }

    func deleteKey(reference: String) throws {
        keys.removeAll { $0.id == reference }
    }

    func savePassword(_ password: String, for profileID: UUID) throws {
        passwords[profileID] = password
    }

    func password(for profileID: UUID) -> String? {
        passwords[profileID]
    }
}

/// Convenience factory for a `KnownHostsStore` seeded with sample fingerprints.
enum PreviewKnownHosts {
    static func populated() -> KnownHostsStore {
        let store = KnownHostsStore()
        store.pin(host: "example.com", port: 22, fingerprint: "SHA256:abcdEFGH1234567890abcdEFGH1234567890abcdEFGH")
        store.pin(host: "homelab.local", port: 2222, fingerprint: "SHA256:zyxwVUTS0987654321zyxwVUTS0987654321zyxwVUTS")
        store.pin(host: "git.internal", port: 22, fingerprint: "SHA256:mnopQRST5555444433332222mnopQRST5555444433")
        return store
    }
}

#endif
