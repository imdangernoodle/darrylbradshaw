import Foundation

/// Pluggable persistence for known host fingerprints. The app provides a
/// file/Keychain-backed implementation; tests use the in-memory one.
public protocol KnownHostsPersistence: AnyObject {
    func load() -> [String: String]
    func save(_ entries: [String: String])
}

public final class InMemoryKnownHostsPersistence: KnownHostsPersistence {
    private var storage: [String: String]

    public init(_ initial: [String: String] = [:]) {
        self.storage = initial
    }

    public func load() -> [String: String] { storage }
    public func save(_ entries: [String: String]) { storage = entries }
}

public enum HostKeyDecision: Equatable {
    case trusted
    case unknown
    case mismatch(expected: String, actual: String)
}

/// Trust-on-first-use (TOFU) store mapping `host[:port]` to a pinned OpenSSH
/// `SHA256:` fingerprint. Existing entries are never silently overwritten — a key
/// change surfaces as `.mismatch` so the user can decide.
public final class KnownHostsStore {
    private let persistence: KnownHostsPersistence
    private var entries: [String: String]

    public init(persistence: KnownHostsPersistence = InMemoryKnownHostsPersistence()) {
        self.persistence = persistence
        self.entries = persistence.load()
    }

    /// Canonical lookup key. The default port is normalized away so `host` and
    /// `host:22` collapse to the same entry, matching OpenSSH's `known_hosts`.
    public static func key(host: String, port: Int) -> String {
        let normalizedHost = host.lowercased()
        return port == ConnectionProfile.defaultPort
            ? normalizedHost
            : "[\(normalizedHost)]:\(port)"
    }

    public func evaluate(host: String, port: Int, fingerprint: String) -> HostKeyDecision {
        guard let known = entries[Self.key(host: host, port: port)] else { return .unknown }
        return known == fingerprint
            ? .trusted
            : .mismatch(expected: known, actual: fingerprint)
    }

    /// Records `fingerprint` only if the host is currently unknown. Returns the
    /// resulting decision (`.trusted` once recorded, or the existing verdict).
    @discardableResult
    public func trustOnFirstUse(host: String, port: Int, fingerprint: String) -> HostKeyDecision {
        let decision = evaluate(host: host, port: port, fingerprint: fingerprint)
        guard decision == .unknown else { return decision }
        entries[Self.key(host: host, port: port)] = fingerprint
        persistence.save(entries)
        return .trusted
    }

    /// Explicitly pin/replace a fingerprint (e.g. the user accepted a changed key).
    public func pin(host: String, port: Int, fingerprint: String) {
        entries[Self.key(host: host, port: port)] = fingerprint
        persistence.save(entries)
    }

    public func forget(host: String, port: Int) {
        entries.removeValue(forKey: Self.key(host: host, port: port))
        persistence.save(entries)
    }

    public func fingerprint(host: String, port: Int) -> String? {
        entries[Self.key(host: host, port: port)]
    }

    public var allEntries: [String: String] { entries }
}
