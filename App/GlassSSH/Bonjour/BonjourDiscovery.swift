import Foundation
import Network
import GlassSSHCore

/// Browses the local network for GlassSSH-relevant Bonjour services and exposes a
/// de-duplicated, observable list of `DiscoveredHost`s.
///
/// Two service types are browsed concurrently:
/// - `_ssh._tcp` → `DiscoveredHost.Kind.ssh`
/// - `_glasspair._tcp` → `DiscoveredHost.Kind.pairing` (the pairing companion)
///
/// `NWBrowser` reports services as opaque endpoints; the instance name is always
/// available, while the concrete host/port require a connection-time resolution.
/// We attempt a best-effort resolution and populate `host`/`port` when the
/// network produces a `hostPort` endpoint, leaving them `nil` otherwise.
///
/// All published mutations happen on the main actor.
@MainActor
final class BonjourDiscovery: ObservableObject, HostDiscovering {
    @Published private(set) var discovered: [DiscoveredHost] = []

    /// One browser per service type, keyed by the kind it discovers.
    private var browsers: [DiscoveredHost.Kind: NWBrowser] = [:]

    /// In-flight resolvers keyed by the discovered host id, so we can cancel them
    /// when the corresponding service disappears.
    private var resolvers: [String: NWConnection] = [:]

    /// Backoff delay (seconds) applied before a browser restart after failure.
    private let restartDelay: TimeInterval = 2

    private let queue = DispatchQueue(label: "com.glassssh.bonjour", qos: .utility)

    /// Service types to browse, paired with the host kind they map to.
    private static let services: [(kind: DiscoveredHost.Kind, type: String)] = [
        (.ssh, "_ssh._tcp"),
        (.pairing, "_glasspair._tcp"),
    ]

    // MARK: - HostDiscovering

    func start() {
        guard browsers.isEmpty else { return }
        for service in Self.services {
            startBrowser(kind: service.kind, type: service.type)
        }
    }

    func stop() {
        for browser in browsers.values {
            browser.cancel()
        }
        browsers.removeAll()
        for resolver in resolvers.values {
            resolver.cancel()
        }
        resolvers.removeAll()
        discovered.removeAll()
    }

    // MARK: - Browsing

    private func startBrowser(kind: DiscoveredHost.Kind, type: String) {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: nil)
        let browser = NWBrowser(for: descriptor, using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed:
                Task { @MainActor in self?.handleBrowserFailure(kind: kind, type: type) }
            case .cancelled, .ready, .setup, .waiting:
                break
            @unknown default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            // `results` is the full current set; snapshot and reconcile on the main actor.
            let snapshot = results
            Task { @MainActor in self?.reconcile(results: snapshot, kind: kind) }
        }

        browsers[kind] = browser
        browser.start(queue: queue)
    }

    private func handleBrowserFailure(kind: DiscoveredHost.Kind, type: String) {
        // Drop the failed browser and any hosts it produced, then schedule a restart.
        browsers[kind]?.cancel()
        browsers[kind] = nil
        removeHosts(ofKind: kind)

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.restartDelay ?? 2) * 1_000_000_000))
            guard let self, self.browsers[kind] == nil else { return }
            self.startBrowser(kind: kind, type: type)
        }
    }

    // MARK: - Reconciliation

    /// Rebuilds the discovered list for a kind from the browser's full result set,
    /// preserving previously-resolved host/port values and resolving new entries.
    private func reconcile(results: Set<NWBrowser.Result>, kind: DiscoveredHost.Kind) {
        var seen: Set<String> = []

        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let id = Self.identifier(name: name, type: type, domain: domain)
            seen.insert(id)

            if let index = discovered.firstIndex(where: { $0.id == id }) {
                // Already known; keep any host/port we previously resolved.
                discovered[index].name = name
            } else {
                let host = DiscoveredHost(id: id, name: name, host: nil, port: nil, kind: kind)
                discovered.append(host)
                resolve(result: result, id: id)
            }
        }

        // Remove hosts of this kind that are no longer advertised.
        let stale = discovered.filter { $0.kind == kind && !seen.contains($0.id) }
        for host in stale {
            resolvers[host.id]?.cancel()
            resolvers[host.id] = nil
        }
        discovered.removeAll { $0.kind == kind && !seen.contains($0.id) }
    }

    private func removeHosts(ofKind kind: DiscoveredHost.Kind) {
        for host in discovered where host.kind == kind {
            resolvers[host.id]?.cancel()
            resolvers[host.id] = nil
        }
        discovered.removeAll { $0.kind == kind }
    }

    // MARK: - Resolution

    /// Best-effort resolution of a service endpoint to a concrete host/port.
    ///
    /// `NWConnection` reports the resolved `hostPort` endpoint once it leaves the
    /// `.preparing` state; we read it, update the model, then tear the probe down.
    private func resolve(result: NWBrowser.Result, id: String) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        resolvers[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready, .preparing:
                guard let resolved = connection.currentPath?.remoteEndpoint,
                      case let .hostPort(host, port) = resolved else {
                    if case .ready = state {
                        Task { @MainActor in self?.finishResolving(id: id) }
                    }
                    return
                }
                let hostString = Self.hostString(from: host)
                let portValue = Int(port.rawValue)
                Task { @MainActor in
                    self?.applyResolution(id: id, host: hostString, port: portValue)
                    self?.finishResolving(id: id)
                }
            case .failed, .cancelled:
                Task { @MainActor in self?.finishResolving(id: id) }
            case .setup, .waiting:
                break
            @unknown default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func applyResolution(id: String, host: String, port: Int) {
        guard let index = discovered.firstIndex(where: { $0.id == id }) else { return }
        discovered[index].host = host
        discovered[index].port = port
    }

    private func finishResolving(id: String) {
        resolvers[id]?.cancel()
        resolvers[id] = nil
    }

    // MARK: - Helpers

    /// Stable identity for a service instance across browse updates.
    private static func identifier(name: String, type: String, domain: String) -> String {
        "\(name).\(type)\(domain)"
    }

    /// Renders an `NWEndpoint.Host` into a display/connect string, stripping the
    /// IPv6 zone identifier that the framework appends for link-local addresses.
    private static func hostString(from host: NWEndpoint.Host) -> String {
        switch host {
        case let .name(name, _):
            return name
        case let .ipv4(address):
            return String(address.debugDescription.split(separator: "%").first ?? "")
        case let .ipv6(address):
            return String(address.debugDescription.split(separator: "%").first ?? "")
        @unknown default:
            return ""
        }
    }
}
