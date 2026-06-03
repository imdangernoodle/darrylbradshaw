import SwiftUI
import GlassSSHCore

/// A single row representing a Bonjour-discovered host: a kind icon, the service
/// instance name, and the resolved `host:port` (or a resolving placeholder).
struct DiscoveredHostRow: View {
    let host: DiscoveredHost

    init(host: DiscoveredHost) {
        self.host = host
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindDescription) \(host.name), \(subtitle)")
    }

    // MARK: - Presentation

    private var subtitle: String {
        switch (host.host, host.port) {
        case let (host?, port?):
            return "\(host):\(port)"
        case let (host?, nil):
            return host
        default:
            return "Resolving…"
        }
    }

    private var iconName: String {
        switch host.kind {
        case .ssh:
            return "terminal"
        case .pairing:
            return "qrcode"
        }
    }

    private var iconColor: Color {
        switch host.kind {
        case .ssh:
            return .accentColor
        case .pairing:
            return .green
        }
    }

    private var kindDescription: String {
        switch host.kind {
        case .ssh:
            return "SSH host"
        case .pairing:
            return "Pairing companion"
        }
    }
}

#Preview {
    List {
        DiscoveredHostRow(
            host: DiscoveredHost(
                id: "mac-mini._ssh._tcp.local.",
                name: "Mac mini",
                host: "192.168.1.42",
                port: 22,
                kind: .ssh
            )
        )
        DiscoveredHostRow(
            host: DiscoveredHost(
                id: "glasspair._glasspair._tcp.local.",
                name: "Studio (pairing)",
                host: nil,
                port: nil,
                kind: .pairing
            )
        )
    }
}
