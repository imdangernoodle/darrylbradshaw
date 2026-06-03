import Foundation
import GlassSSHCore

/// Stable interfaces the subsystems implement, so the UI and coordinator depend on
/// protocols rather than concrete types. This keeps the parallel work units
/// decoupled — each unit provides a conforming implementation, and final wiring
/// swaps the scaffold's stubs for the real ones.

@MainActor
public protocol ProfileStoring: AnyObject {
    var profiles: [ConnectionProfile] { get }
    func add(_ profile: ConnectionProfile)
    func update(_ profile: ConnectionProfile)
    func remove(_ profile: ConnectionProfile)
    func reload()
}

/// A host discovered on the local network via Bonjour.
public struct DiscoveredHost: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case ssh        // _ssh._tcp
        case pairing    // _glasspair._tcp
    }
    public var id: String
    public var name: String
    public var host: String?
    public var port: Int?
    public var kind: Kind

    public init(id: String, name: String, host: String?, port: Int?, kind: Kind) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.kind = kind
    }
}

@MainActor
public protocol HostDiscovering: AnyObject {
    var discovered: [DiscoveredHost] { get }
    func start()
    func stop()
}

/// A managed SSH key (metadata only — private material stays in the Secure Enclave).
public struct ManagedKey: Identifiable, Hashable, Sendable {
    public var id: String        // Keychain / Secure Enclave reference tag
    public var label: String
    public var openSSHPublicKey: String
    public var createdAt: Date

    public init(id: String, label: String, openSSHPublicKey: String, createdAt: Date) {
        self.id = id
        self.label = label
        self.openSSHPublicKey = openSSHPublicKey
        self.createdAt = createdAt
    }
}

/// Manages SSH key material (Secure Enclave) and per-profile password secrets.
@MainActor
public protocol CredentialManaging: AnyObject {
    var keys: [ManagedKey] { get }
    func generateKey(label: String) throws -> ManagedKey
    func deleteKey(reference: String) throws
    func savePassword(_ password: String, for profileID: UUID) throws
    func password(for profileID: UUID) -> String?
}
