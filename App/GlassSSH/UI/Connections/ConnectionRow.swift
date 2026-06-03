import SwiftUI
import GlassSSHCore

/// A single row in the connections sidebar. Renders either a saved
/// `ConnectionProfile` or a live-discovered `DiscoveredHost`, sharing one glassy
/// presentation so the two list sections feel like one surface.
struct ConnectionRow: View {
    enum Content {
        case profile(ConnectionProfile)
        case discovered(DiscoveredHost)
    }

    let content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(symbolColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if case .discovered = content {
                liveBadge
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var liveBadge: some View {
        Text("Live")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(GlassPalette.success)
            .glassCard(cornerRadius: 8)
    }

    // MARK: - Presentation

    private var title: String {
        switch content {
        case let .profile(profile):
            return profile.name.isEmpty ? profile.displayDestination : profile.name
        case let .discovered(host):
            return host.name
        }
    }

    private var subtitle: String {
        switch content {
        case let .profile(profile):
            return profile.displayDestination
        case let .discovered(host):
            if let address = host.host {
                let port = host.port ?? ConnectionProfile.defaultPort
                return port == ConnectionProfile.defaultPort ? address : "\(address):\(port)"
            }
            return host.kind == .pairing ? "Ready to pair" : "Resolving…"
        }
    }

    private var symbolName: String {
        switch content {
        case .profile:
            return "terminal"
        case let .discovered(host):
            return host.kind == .pairing ? "qrcode" : "wifi"
        }
    }

    private var symbolColor: Color {
        switch content {
        case .profile:
            return GlassPalette.accent
        case let .discovered(host):
            return host.kind == .pairing ? GlassPalette.warning : GlassPalette.accent
        }
    }
}
