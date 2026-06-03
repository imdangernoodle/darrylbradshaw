import Foundation
import Combine
import GlassSSHCore

/// Disk-backed store for `ConnectionProfile` metadata.
///
/// Profiles are persisted as a single JSON array in Application Support using
/// atomic writes, so a crash or interrupted write can never leave a partially
/// serialized file behind. Secrets (passwords, private keys) are *never* stored
/// here — they live in the Keychain / Secure Enclave and are referenced
/// indirectly from `ConnectionProfile` (see `keyReference`). This type only ever
/// touches non-sensitive connection metadata.
///
/// Conforms to ``ProfileStoring`` so the UI and coordinator depend on the
/// protocol rather than this concrete implementation.
@MainActor
public final class ProfileStore: ObservableObject, ProfileStoring {
    /// The current set of saved profiles, sorted for a stable presentation order.
    /// Mutations are published so SwiftUI views refresh automatically.
    @Published public private(set) var profiles: [ConnectionProfile] = []

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a store backed by a JSON file.
    ///
    /// - Parameters:
    ///   - fileURL: Location of the JSON file. Defaults to
    ///     `Application Support/GlassSSH/profiles.json`.
    ///   - fileManager: Injected for testability; defaults to `.default`.
    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        reload()
    }

    // MARK: - ProfileStoring

    /// Adds a new profile, or replaces any existing profile with the same `id`.
    public func add(_ profile: ConnectionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        normalizeAndPersist()
    }

    /// Updates an existing profile in place. If no profile with a matching `id`
    /// exists, the profile is inserted (upsert semantics).
    public func update(_ profile: ConnectionProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            add(profile)
            return
        }
        profiles[index] = profile
        normalizeAndPersist()
    }

    /// Removes the profile matching `profile.id`, if present.
    public func remove(_ profile: ConnectionProfile) {
        let original = profiles
        profiles.removeAll { $0.id == profile.id }
        guard profiles != original else { return }
        persist()
    }

    /// Reloads profiles from disk, discarding any unsaved in-memory state.
    ///
    /// A missing file is treated as an empty store (first launch). A corrupt or
    /// unreadable file is logged and likewise yields an empty store rather than
    /// crashing — the user can simply re-add their destinations.
    public func reload() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            profiles = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                profiles = []
                return
            }
            let decoded = try decoder.decode([ConnectionProfile].self, from: data)
            profiles = Self.sorted(decoded)
        } catch {
            // Don't lose the user's ability to use the app over a bad file; start
            // empty and let subsequent writes heal the on-disk state.
            assertionFailure("Failed to load profiles: \(error)")
            profiles = []
        }
    }

    // MARK: - Persistence

    /// Re-sorts the in-memory list and writes it to disk.
    private func normalizeAndPersist() {
        profiles = Self.sorted(profiles)
        persist()
    }

    /// Atomically serializes `profiles` to `fileURL`.
    private func persist() {
        do {
            try ensureContainerExists()
            let data = try encoder.encode(profiles)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistence failures are non-fatal: the in-memory state remains the
            // source of truth for this session and the next write will retry.
            assertionFailure("Failed to persist profiles: \(error)")
        }
    }

    private func ensureContainerExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Helpers

    /// Stable ordering: alphabetical by name (case-insensitive), then by
    /// creation date and finally `id` to fully disambiguate.
    private static func sorted(_ profiles: [ConnectionProfile]) -> [ConnectionProfile] {
        profiles.sorted { lhs, rhs in
            let byName = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if byName != .orderedSame {
                return byName == .orderedAscending
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
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
            .appendingPathComponent("profiles.json", isDirectory: false)
    }
}
