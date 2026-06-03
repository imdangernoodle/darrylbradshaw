import Foundation
import GlassSSHCore

/// Routes incoming `glassssh://` URLs (from a scanned QR or a deep link) to the
/// appropriate Core codec and surfaces a strongly-typed result for the UI to act
/// on. Decoding itself lives in `GlassSSHCore` (`ProfileQRCodec` / `PairingCodec`);
/// this type only dispatches on the URL's action and maps failures to `.invalid`.
enum GlassSSHURLRouter {
    /// The outcome of routing a single URL.
    enum Result: Equatable {
        /// A `glassssh://connect?...` URL carrying an importable connection.
        case importProfile(ConnectionProfile)
        /// A `glassssh://pair?...` URL carrying a Bonjour pairing payload.
        case pairing(PairingPayload)
        /// The URL was not a recognizable, well-formed `glassssh://` link.
        case invalid
    }

    /// Decodes the given URL into a routing result.
    ///
    /// Any malformed input, wrong scheme, or unknown action collapses to
    /// `.invalid` rather than throwing — callers present a single user-facing
    /// "couldn't read that code" state regardless of the underlying reason.
    static func route(_ url: URL) -> Result {
        guard url.scheme == ProfileQRCodec.scheme else { return .invalid }

        switch url.host {
        case ProfileQRCodec.connectAction:
            guard let profile = try? ProfileQRCodec.profile(from: url) else { return .invalid }
            return .importProfile(profile)
        case PairingCodec.pairAction:
            guard let payload = try? PairingCodec.payload(from: url) else { return .invalid }
            return .pairing(payload)
        default:
            return .invalid
        }
    }

    /// Convenience for routing a raw scanned string.
    static func route(string: String) -> Result {
        guard let url = URL(string: string) else { return .invalid }
        return route(url)
    }
}
