import Foundation
import SwiftUI
import GlassSSHCore

/// App-wide coordinator. Holds shared state and routes deep links. Subsystem
/// dependencies are protocol-typed and default to lightweight stubs so the
/// scaffold compiles on its own; final integration injects the real
/// implementations provided by the work units.
@MainActor
final class AppModel: ObservableObject {
    /// Set when an incoming `glassssh://` link should present an import sheet.
    @Published var pendingImport: ConnectionProfile?

    /// Trust-on-first-use host key store (file-backed implementation supplied by
    /// the Data unit; defaults to in-memory here).
    let knownHosts = KnownHostsStore()

    func handleIncomingURL(_ url: URL) {
        if let profile = try? ProfileQRCodec.profile(from: url) {
            pendingImport = profile
        } else if let payload = try? PairingCodec.payload(from: url) {
            pendingImport = payload.makeProfile()
        }
    }
}
