import Foundation
import Combine
import CryptoKit
import GlassSSHCore

/// Concrete ``CredentialManaging`` implementation backed by the Secure Enclave
/// (for SSH key material) and the Keychain (for the enclave key blobs and
/// per-profile passwords).
///
/// ## What lives where
/// - **SSH private keys** are generated *inside the Secure Enclave*. The private
///   material never leaves the hardware; we persist only an opaque, enclave-bound
///   blob (see ``SecureEnclaveKey``). That blob is stored as a Keychain
///   generic-password item tagged with an *application tag* string — the tag is
///   the public ``ManagedKey/id`` ("reference") the rest of the app passes around.
/// - **Public keys** are exported in OpenSSH `ecdsa-sha2-nistp256` format so the
///   user can paste them into a server's `authorized_keys`.
/// - **Per-profile passwords** are stored as separate generic-password Keychain
///   items keyed by the profile's `UUID`.
///
/// To actually authenticate over SSH, the app loads the enclave key for a given
/// reference and wraps it with ``SecureEnclaveSSHSigner`` to obtain a
/// `NIOSSHPrivateKey`.
@MainActor
public final class KeyStore: ObservableObject, CredentialManaging {

    public enum Failure: Error, CustomStringConvertible {
        case duplicateLabel(String)
        case keyNotFound(String)
        case keychainError(OSStatus)
        case metadataCorrupted(String)

        public var description: String {
            switch self {
            case .duplicateLabel(let label):
                return "A key labelled \"\(label)\" already exists."
            case .keyNotFound(let reference):
                return "No Secure Enclave key found for reference \"\(reference)\"."
            case .keychainError(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
                return "Keychain operation failed: \(message)"
            case .metadataCorrupted(let detail):
                return "Stored key metadata is corrupted: \(detail)"
            }
        }
    }

    /// Service identifiers namespacing our Keychain items.
    private enum Service {
        static let enclaveKey = "com.glassssh.securekey"
        static let password = "com.glassssh.password"
    }

    @Published public private(set) var keys: [ManagedKey] = []

    /// Optional Keychain access-group, for sharing items with extensions. `nil`
    /// uses the app's default group.
    private let accessGroup: String?

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
        reload()
    }

    /// Reloads the published `keys` list from the Keychain.
    public func reload() {
        keys = (try? loadAllKeys()) ?? []
    }

    // MARK: - Key management

    public func generateKey(label: String) throws -> ManagedKey {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        // Check against the Keychain (the source of truth) rather than the cached
        // `keys` list: `reload()` may have produced a stale/empty cache if a
        // transient Keychain read failed (e.g. queried while the device was
        // locked), and we must not silently create a second key with this label.
        if try loadAllKeys().contains(where: { $0.label == trimmedLabel }) {
            throw Failure.duplicateLabel(trimmedLabel)
        }

        let privateKey = try SecureEnclaveKey.generateKey()
        let reference = "glassssh-key-\(UUID().uuidString)"
        let createdAt = Date()

        let openSSHPublicKey = privateKey.publicKey.openSSHAuthorizedKey(comment: trimmedLabel)
        let record = StoredKeyRecord(
            label: trimmedLabel,
            openSSHPublicKey: openSSHPublicKey,
            createdAt: createdAt
        )

        try addEnclaveKeyItem(
            tag: reference,
            blob: privateKey.dataRepresentation,
            metadata: record
        )

        let managed = ManagedKey(
            id: reference,
            label: trimmedLabel,
            openSSHPublicKey: openSSHPublicKey,
            createdAt: createdAt
        )
        keys.append(managed)
        keys.sort { $0.createdAt < $1.createdAt }
        return managed
    }

    public func deleteKey(reference: String) throws {
        let query = enclaveKeyQuery(tag: reference)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychainError(status)
        }
        keys.removeAll { $0.id == reference }
    }

    /// Loads the persisted enclave key for a reference and reconstructs the
    /// signing key. Used by ``SecureEnclaveSSHSigner`` to build the NIOSSH key.
    func loadSigningKey(reference: String) throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard let blob = try loadEnclaveKeyBlob(tag: reference) else {
            throw Failure.keyNotFound(reference)
        }
        return try SecureEnclaveKey.loadKey(blob: blob)
    }

    // MARK: - Password secrets

    public func savePassword(_ password: String, for profileID: UUID) throws {
        let account = profileID.uuidString
        let data = Data(password.utf8)

        var attributes = baseQuery(service: Service.password, account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let query = baseQuery(service: Service.password, account: account)
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw Failure.keychainError(updateStatus)
            }
        default:
            throw Failure.keychainError(addStatus)
        }
    }

    public func password(for profileID: UUID) -> String? {
        var query = baseQuery(service: Service.password, account: profileID.uuidString)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes a stored password. Not part of the protocol, but the natural
    /// counterpart to ``savePassword(_:for:)`` for profile teardown.
    public func deletePassword(for profileID: UUID) throws {
        let query = baseQuery(service: Service.password, account: profileID.uuidString)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychainError(status)
        }
    }

    // MARK: - Keychain plumbing (enclave key blobs)

    private func addEnclaveKeyItem(tag: String, blob: Data, metadata: StoredKeyRecord) throws {
        let metadataData = try JSONEncoder().encode(metadata)

        var attributes = baseQuery(service: Service.enclaveKey, account: tag)
        // We persist the enclave key blob as the item's value and the public
        // metadata (label, OpenSSH key, timestamp) in the generic attribute.
        attributes[kSecValueData as String] = blob
        attributes[kSecAttrGeneric as String] = metadataData
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Failure.keychainError(status)
        }
    }

    private func loadEnclaveKeyBlob(tag: String) throws -> Data? {
        var query = enclaveKeyQuery(tag: tag)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychainError(status)
        }
    }

    private func loadAllKeys() throws -> [ManagedKey] {
        var query = baseQuery(service: Service.enclaveKey, account: nil)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecItemNotFound:
            return []
        case errSecSuccess:
            break
        default:
            throw Failure.keychainError(status)
        }

        guard let items = result as? [[String: Any]] else { return [] }

        let decoder = JSONDecoder()
        var managed: [ManagedKey] = []
        for item in items {
            guard
                let account = item[kSecAttrAccount as String] as? String,
                let metadataData = item[kSecAttrGeneric as String] as? Data,
                let record = try? decoder.decode(StoredKeyRecord.self, from: metadataData)
            else {
                continue
            }
            managed.append(
                ManagedKey(
                    id: account,
                    label: record.label,
                    openSSHPublicKey: record.openSSHPublicKey,
                    createdAt: record.createdAt
                )
            )
        }
        return managed.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Query builders

    /// The base attributes shared by every generic-password item we store.
    /// Passing `account == nil` yields a service-wide query (used to list keys).
    private func baseQuery(service: String, account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// Query for a single enclave-key item, matched by its application tag.
    private func enclaveKeyQuery(tag: String) -> [String: Any] {
        baseQuery(service: Service.enclaveKey, account: tag)
    }
}

/// Public metadata persisted alongside each enclave key blob. Kept separate from
/// `ManagedKey` so the wire/storage format can evolve independently of the
/// app-facing model.
private struct StoredKeyRecord: Codable {
    var label: String
    var openSSHPublicKey: String
    var createdAt: Date
}
