import XCTest
@testable import GlassSSHCore

final class PairingCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let expiry = Date(timeIntervalSince1970: 1_900_000_000)
        let payload = PairingPayload(
            host: "10.0.0.5",
            port: 22,
            username: "deploy",
            serviceName: "studio-mac",
            hostFingerprint: "SHA256:zzz",
            token: "one-time-token",
            expiresAt: expiry
        )

        let url = PairingCodec.makeURL(from: payload)
        XCTAssertEqual(url.scheme, "glassssh")
        XCTAssertEqual(url.host, "pair")

        let decoded = try PairingCodec.payload(from: url)
        XCTAssertEqual(decoded.host, payload.host)
        XCTAssertEqual(decoded.port, payload.port)
        XCTAssertEqual(decoded.username, payload.username)
        XCTAssertEqual(decoded.serviceName, payload.serviceName)
        XCTAssertEqual(decoded.hostFingerprint, payload.hostFingerprint)
        XCTAssertEqual(decoded.token, payload.token)
        XCTAssertEqual(decoded.expiresAt, expiry)
    }

    func testMissingTokenThrows() {
        let urlString = "glassssh://pair?host=h&service=s&fp=SHA256:x"
        XCTAssertThrowsError(try PairingCodec.payload(fromString: urlString)) { error in
            XCTAssertEqual(error as? QRCodecError, .missingField("token"))
        }
    }

    func testExpiryEvaluation() {
        let past = PairingPayload(
            host: "h", serviceName: "s", hostFingerprint: "SHA256:x", token: "t",
            expiresAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(past.isExpired(asOf: Date(timeIntervalSince1970: 1)))

        let noExpiry = PairingPayload(host: "h", serviceName: "s", hostFingerprint: "SHA256:x", token: "t")
        XCTAssertFalse(noExpiry.isExpired())
    }

    func testMakeProfilePinsFingerprint() {
        let payload = PairingPayload(
            host: "h", port: 2200, username: "u",
            serviceName: "svc", hostFingerprint: "SHA256:pinned", token: "t"
        )
        let profile = payload.makeProfile()
        XCTAssertEqual(profile.host, "h")
        XCTAssertEqual(profile.port, 2200)
        XCTAssertEqual(profile.username, "u")
        XCTAssertEqual(profile.pinnedHostFingerprint, "SHA256:pinned")
    }
}
