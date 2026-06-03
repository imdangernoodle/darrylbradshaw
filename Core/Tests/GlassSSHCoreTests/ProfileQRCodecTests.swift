import XCTest
@testable import GlassSSHCore

final class ProfileQRCodecTests: XCTestCase {
    func testRoundTripPreservesFields() throws {
        let original = ConnectionProfile(
            name: "Prod box",
            host: "example.com",
            port: 2222,
            username: "alice",
            authMethod: .publicKey,
            keyReference: "se-key-1",
            pinnedHostFingerprint: "SHA256:abc123"
        )

        let url = ProfileQRCodec.makeURL(from: original)
        XCTAssertEqual(url.scheme, "glassssh")
        XCTAssertEqual(url.host, "connect")

        let decoded = try ProfileQRCodec.profile(from: url)
        XCTAssertEqual(decoded.host, original.host)
        XCTAssertEqual(decoded.port, original.port)
        XCTAssertEqual(decoded.username, original.username)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.authMethod, original.authMethod)
        XCTAssertEqual(decoded.keyReference, original.keyReference)
        XCTAssertEqual(decoded.pinnedHostFingerprint, original.pinnedHostFingerprint)
    }

    func testDefaultsPortAndAuthWhenOmitted() throws {
        let profile = try ProfileQRCodec.profile(fromString: "glassssh://connect?host=h.example&user=bob")
        XCTAssertEqual(profile.port, ConnectionProfile.defaultPort)
        XCTAssertEqual(profile.authMethod, .password)
        XCTAssertEqual(profile.name, "h.example") // falls back to host
    }

    func testMissingRequiredFieldThrows() {
        XCTAssertThrowsError(try ProfileQRCodec.profile(fromString: "glassssh://connect?host=h.example")) { error in
            XCTAssertEqual(error as? QRCodecError, .missingField("user"))
        }
    }

    func testWrongSchemeThrows() {
        XCTAssertThrowsError(try ProfileQRCodec.profile(fromString: "https://connect?host=h&user=u")) { error in
            XCTAssertEqual(error as? QRCodecError, .wrongScheme("https"))
        }
    }

    func testUnknownActionThrows() {
        XCTAssertThrowsError(try ProfileQRCodec.profile(fromString: "glassssh://pair?host=h&user=u")) { error in
            XCTAssertEqual(error as? QRCodecError, .unknownAction("pair"))
        }
    }

    func testInvalidPortThrows() {
        XCTAssertThrowsError(try ProfileQRCodec.profile(fromString: "glassssh://connect?host=h&user=u&port=99999")) { error in
            XCTAssertEqual(error as? QRCodecError, .invalidPort("99999"))
        }
    }

    func testHostWithSpecialCharactersSurvivesEncoding() throws {
        let original = ConnectionProfile(name: "My Server", host: "fe80::1", username: "root")
        let decoded = try ProfileQRCodec.profile(from: ProfileQRCodec.makeURL(from: original))
        XCTAssertEqual(decoded.host, "fe80::1")
        XCTAssertEqual(decoded.name, "My Server")
    }
}
