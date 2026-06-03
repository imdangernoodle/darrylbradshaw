import Foundation

public enum QRCodecError: Error, Equatable {
    case invalidURL
    case wrongScheme(String?)
    case unknownAction(String?)
    case missingField(String)
    case invalidPort(String)
}

/// Encodes / decodes a `ConnectionProfile` to a `glassssh://connect?...` URL that
/// can be rendered as a QR code and scanned to import a destination on the iPad.
///
/// Deliberately carries no secrets — only enough metadata to populate a new
/// connection. Passwords and private keys are entered/stored on-device.
public enum ProfileQRCodec {
    public static let scheme = "glassssh"
    public static let connectAction = "connect"

    public static func makeURL(from profile: ConnectionProfile) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = connectAction
        var items: [URLQueryItem] = [
            URLQueryItem(name: "host", value: profile.host),
            URLQueryItem(name: "port", value: String(profile.port)),
            URLQueryItem(name: "user", value: profile.username),
            URLQueryItem(name: "name", value: profile.name),
            URLQueryItem(name: "auth", value: profile.authMethod.rawValue),
        ]
        if let fingerprint = profile.pinnedHostFingerprint {
            items.append(URLQueryItem(name: "fp", value: fingerprint))
        }
        if let key = profile.keyReference {
            items.append(URLQueryItem(name: "key", value: key))
        }
        components.queryItems = items
        // Safe by construction: scheme, host and query items are all valid.
        return components.url!
    }

    public static func makeURLString(from profile: ConnectionProfile) -> String {
        makeURL(from: profile).absoluteString
    }

    public static func profile(from url: URL) throws -> ConnectionProfile {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw QRCodecError.invalidURL
        }
        guard components.scheme == scheme else {
            throw QRCodecError.wrongScheme(components.scheme)
        }
        guard components.host == connectAction else {
            throw QRCodecError.unknownAction(components.host)
        }

        let query = QueryDecoding.dictionary(from: components.queryItems)

        let host = try QueryDecoding.required(query, "host")
        let user = try QueryDecoding.required(query, "user")

        let portString = query["port"].flatMap { $0.isEmpty ? nil : $0 }
            ?? String(ConnectionProfile.defaultPort)
        guard let port = Int(portString), (1...65_535).contains(port) else {
            throw QRCodecError.invalidPort(portString)
        }

        let authMethod = ConnectionProfile.AuthMethod(rawValue: query["auth"] ?? "") ?? .password
        let name = query["name"].flatMap { $0.isEmpty ? nil : $0 } ?? host

        return ConnectionProfile(
            name: name,
            host: host,
            port: port,
            username: user,
            authMethod: authMethod,
            keyReference: query["key"].flatMap { $0.isEmpty ? nil : $0 },
            pinnedHostFingerprint: query["fp"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    public static func profile(fromString string: String) throws -> ConnectionProfile {
        guard let url = URL(string: string) else { throw QRCodecError.invalidURL }
        return try profile(from: url)
    }
}

/// Shared query-string helpers for the `glassssh://` codecs.
enum QueryDecoding {
    static func dictionary(from items: [URLQueryItem]?) -> [String: String] {
        Dictionary(
            (items ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { _, last in last }
        )
    }

    static func required(_ query: [String: String], _ key: String) throws -> String {
        guard let value = query[key], !value.isEmpty else {
            throw QRCodecError.missingField(key)
        }
        return value
    }
}
