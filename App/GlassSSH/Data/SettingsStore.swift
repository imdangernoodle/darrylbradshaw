import Foundation
import Combine
import GlassSSHCore

/// User-facing, non-secret application settings.
///
/// This is pure preference data (appearance, defaults, behavior toggles) — it
/// holds no passwords or key material. It is `Codable` so it can be persisted
/// and migrated cleanly.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Preferred color scheme for the app's chrome and terminal.
    public enum ColorSchemePreference: String, Codable, CaseIterable, Sendable {
        case system
        case light
        case dark
    }

    /// Terminal monospaced font size, in points. Clamped to a sane range.
    public var terminalFontSize: Double

    /// Preferred color scheme.
    public var colorScheme: ColorSchemePreference

    /// Username prefilled when creating a new connection profile. May be empty.
    public var defaultUsername: String

    /// When `true`, a previously unknown host key is automatically pinned on
    /// first connect (trust-on-first-use). When `false`, the user is prompted to
    /// confirm before pinning.
    public var autoPinHostKeys: Bool

    /// Allowed range for ``terminalFontSize``.
    public static let fontSizeRange: ClosedRange<Double> = 8...32

    public static let `default` = AppSettings(
        terminalFontSize: 14,
        colorScheme: .system,
        defaultUsername: "",
        autoPinHostKeys: true
    )

    public init(
        terminalFontSize: Double = AppSettings.default.terminalFontSize,
        colorScheme: ColorSchemePreference = AppSettings.default.colorScheme,
        defaultUsername: String = AppSettings.default.defaultUsername,
        autoPinHostKeys: Bool = AppSettings.default.autoPinHostKeys
    ) {
        self.terminalFontSize = terminalFontSize
        self.colorScheme = colorScheme
        self.defaultUsername = defaultUsername
        self.autoPinHostKeys = autoPinHostKeys
    }

    /// Returns a copy with values constrained to valid ranges.
    public func normalized() -> AppSettings {
        var copy = self
        copy.terminalFontSize = min(
            max(terminalFontSize, AppSettings.fontSizeRange.lowerBound),
            AppSettings.fontSizeRange.upperBound
        )
        return copy
    }

    // Tolerate older/partial payloads by defaulting any missing field, so adding
    // a setting in a future version doesn't invalidate a user's saved file.
    private enum CodingKeys: String, CodingKey {
        case terminalFontSize, colorScheme, defaultUsername, autoPinHostKeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        self.terminalFontSize = try container.decodeIfPresent(
            Double.self, forKey: .terminalFontSize) ?? fallback.terminalFontSize
        // Decode the raw string so an unrecognized value (e.g. one written by a
        // newer build) degrades to the default scheme instead of throwing and
        // discarding every other setting.
        let rawScheme = try container.decodeIfPresent(String.self, forKey: .colorScheme)
        self.colorScheme = rawScheme.flatMap(ColorSchemePreference.init(rawValue:))
            ?? fallback.colorScheme
        self.defaultUsername = try container.decodeIfPresent(
            String.self, forKey: .defaultUsername) ?? fallback.defaultUsername
        self.autoPinHostKeys = try container.decodeIfPresent(
            Bool.self, forKey: .autoPinHostKeys) ?? fallback.autoPinHostKeys
    }
}

/// Observable, persisted holder for ``AppSettings``.
///
/// Settings are stored as a single JSON blob in `UserDefaults`, which is the
/// natural home for small user preferences. Mutations to ``settings`` are
/// published for SwiftUI and written through to `UserDefaults` immediately. No
/// secrets are stored here.
@MainActor
public final class SettingsStore: ObservableObject {
    /// The current settings. Assigning a new value persists it (after
    /// normalization) and publishes the change.
    @Published public var settings: AppSettings {
        didSet {
            let normalized = settings.normalized()
            // Avoid a publish/persist loop if normalization changed nothing.
            if normalized != settings {
                settings = normalized
                return
            }
            persist()
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a settings store.
    ///
    /// - Parameters:
    ///   - defaults: Backing store; defaults to `.standard`. Injectable for tests.
    ///   - storageKey: Key under which the JSON blob is stored.
    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.glassssh.settings"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.settings = Self.load(
            from: defaults,
            key: storageKey,
            decoder: decoder
        )
    }

    /// Restores all settings to their defaults and persists the change.
    public func resetToDefaults() {
        settings = .default
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try encoder.encode(settings)
            defaults.set(data, forKey: storageKey)
        } catch {
            assertionFailure("Failed to persist settings: \(error)")
        }
    }

    private static func load(
        from defaults: UserDefaults,
        key: String,
        decoder: JSONDecoder
    ) -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return .default }
        do {
            return try decoder.decode(AppSettings.self, from: data).normalized()
        } catch {
            assertionFailure("Failed to load settings: \(error)")
            return .default
        }
    }
}
