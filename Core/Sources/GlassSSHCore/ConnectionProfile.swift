import Foundation

/// A saved SSH destination. This is pure metadata — secrets (passwords, private
/// keys) are *never* stored here. They live in the Keychain / Secure Enclave and
/// are referenced indirectly via `keyReference`.
public struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
    public enum AuthMethod: String, Codable, Sendable, CaseIterable {
        case password
        case publicKey
    }

    public static let defaultPort = 22

    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: AuthMethod
    /// Keychain / Secure Enclave tag identifying the key used when
    /// `authMethod == .publicKey`. Never the key material itself.
    public var keyReference: String?
    /// Pinned host public-key fingerprint in OpenSSH `SHA256:...` form, used for
    /// trust-on-first-use verification on subsequent connects.
    public var pinnedHostFingerprint: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = ConnectionProfile.defaultPort,
        username: String,
        authMethod: AuthMethod = .password,
        keyReference: String? = nil,
        pinnedHostFingerprint: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.keyReference = keyReference
        self.pinnedHostFingerprint = pinnedHostFingerprint
        self.createdAt = createdAt
    }
}

public extension ConnectionProfile {
    /// A short, user-facing label like `alice@example.com` or `alice@host:2222`.
    var displayDestination: String {
        port == ConnectionProfile.defaultPort
            ? "\(username)@\(host)"
            : "\(username)@\(host):\(port)"
    }

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && (1...65_535).contains(port)
    }
}
