import Foundation
import GlassSSHCore

/// File-backed implementation of ``KnownHostsPersistence``.
///
/// Persists the trust-on-first-use (TOFU) known-hosts map — a dictionary of
/// canonical `host[:port]` keys to pinned OpenSSH `SHA256:` fingerprints — as
/// JSON on disk in Application Support, using atomic writes. This lets a
/// `KnownHostsStore` survive app launches so previously trusted host keys stay
/// pinned.
///
/// Fingerprints are public, non-secret data (a hash of the server's public host
/// key), so plain on-disk JSON is appropriate here. No private material is ever
/// written by this type.
public final class FileKnownHostsPersistence: KnownHostsPersistence {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a persistence backed by a JSON file.
    ///
    /// - Parameters:
    ///   - fileURL: Location of the JSON file. Defaults to
    ///     `Application Support/GlassSSH/known_hosts.json`.
    ///   - fileManager: Injected for testability; defaults to `.default`.
    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    // MARK: - KnownHostsPersistence

    /// Loads the known-hosts map from disk.
    ///
    /// A missing file is treated as an empty map (first launch). A corrupt or
    /// unreadable file yields an empty map rather than crashing — a subsequent
    /// `save(_:)` heals the on-disk state.
    public func load() -> [String: String] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return [:] }
            return try decoder.decode([String: String].self, from: data)
        } catch {
            assertionFailure("Failed to load known hosts: \(error)")
            return [:]
        }
    }

    /// Atomically writes the known-hosts map to disk.
    public func save(_ entries: [String: String]) {
        do {
            try ensureContainerExists()
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Non-fatal: the caller's in-memory state remains authoritative and
            // the next save will retry.
            assertionFailure("Failed to save known hosts: \(error)")
        }
    }

    // MARK: - Helpers

    private func ensureContainerExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        return base
            .appendingPathComponent("GlassSSH", isDirectory: true)
            .appendingPathComponent("known_hosts.json", isDirectory: false)
    }
}
