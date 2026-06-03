import Foundation

/// Payload carried by the QR code shown by the Bonjour pairing companion
/// (`Companion/glasspair.py`). The companion advertises itself over Bonjour and
/// prints this as a QR so the iPad can pin the host key (trust-on-first-use) and
/// connect with a single tap.
///
/// Encoded as `glassssh://pair?...`.
public struct PairingPayload: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var username: String?
    /// The Bonjour service instance name the companion advertises.
    public var serviceName: String
    /// OpenSSH `SHA256:...` fingerprint of the server's host key, to be pinned.
    public var hostFingerprint: String
    /// One-time pairing token the companion can verify on first connect.
    public var token: String
    /// Optional expiry; pairing QRs are short-lived by design.
    public var expiresAt: Date?

    public init(
        host: String,
        port: Int = ConnectionProfile.defaultPort,
        username: String? = nil,
        serviceName: String,
        hostFingerprint: String,
        token: String,
        expiresAt: Date? = nil
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.serviceName = serviceName
        self.hostFingerprint = hostFingerprint
        self.token = token
        self.expiresAt = expiresAt
    }

    public func isExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// Builds an importable connection profile from this pairing payload.
    public func makeProfile() -> ConnectionProfile {
        ConnectionProfile(
            name: serviceName,
            host: host,
            port: port,
            username: username ?? "",
            authMethod: .password,
            pinnedHostFingerprint: hostFingerprint
        )
    }
}

public enum PairingCodec {
    public static let scheme = ProfileQRCodec.scheme
    public static let pairAction = "pair"

    public static func makeURL(from payload: PairingPayload) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = pairAction
        var items: [URLQueryItem] = [
            URLQueryItem(name: "host", value: payload.host),
            URLQueryItem(name: "port", value: String(payload.port)),
            URLQueryItem(name: "service", value: payload.serviceName),
            URLQueryItem(name: "fp", value: payload.hostFingerprint),
            URLQueryItem(name: "token", value: payload.token),
        ]
        if let username = payload.username {
            items.append(URLQueryItem(name: "user", value: username))
        }
        if let expiresAt = payload.expiresAt {
            let epoch = Int(expiresAt.timeIntervalSince1970.rounded())
            items.append(URLQueryItem(name: "exp", value: String(epoch)))
        }
        components.queryItems = items
        return components.url!
    }

    public static func makeURLString(from payload: PairingPayload) -> String {
        makeURL(from: payload).absoluteString
    }

    public static func payload(from url: URL) throws -> PairingPayload {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw QRCodecError.invalidURL
        }
        guard components.scheme == scheme else {
            throw QRCodecError.wrongScheme(components.scheme)
        }
        guard components.host == pairAction else {
            throw QRCodecError.unknownAction(components.host)
        }

        let query = QueryDecoding.dictionary(from: components.queryItems)

        let host = try QueryDecoding.required(query, "host")
        let serviceName = try QueryDecoding.required(query, "service")
        let fingerprint = try QueryDecoding.required(query, "fp")
        let token = try QueryDecoding.required(query, "token")

        let portString = query["port"].flatMap { $0.isEmpty ? nil : $0 }
            ?? String(ConnectionProfile.defaultPort)
        guard let port = Int(portString), (1...65_535).contains(port) else {
            throw QRCodecError.invalidPort(portString)
        }

        let expiresAt = query["exp"]
            .flatMap { Int($0) }
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }

        return PairingPayload(
            host: host,
            port: port,
            username: query["user"].flatMap { $0.isEmpty ? nil : $0 },
            serviceName: serviceName,
            hostFingerprint: fingerprint,
            token: token,
            expiresAt: expiresAt
        )
    }

    public static func payload(fromString string: String) throws -> PairingPayload {
        guard let url = URL(string: string) else { throw QRCodecError.invalidURL }
        return try payload(from: url)
    }
}
