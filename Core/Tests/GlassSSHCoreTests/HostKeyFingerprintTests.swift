import XCTest
@testable import GlassSSHCore

final class HostKeyFingerprintTests: XCTestCase {
    /// Well-known value: SHA-256 of the empty input, OpenSSH base64 (no padding).
    func testEmptyBlobMatchesKnownVector() {
        let fingerprint = HostKeyFingerprint.sha256(ofPublicKeyBlob: Data())
        XCTAssertEqual(fingerprint, "SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU")
    }

    func testFingerprintHasNoBase64Padding() {
        let fingerprint = HostKeyFingerprint.sha256(ofPublicKeyBlob: Data([0x01, 0x02, 0x03]))
        XCTAssertTrue(fingerprint.hasPrefix("SHA256:"))
        XCTAssertFalse(fingerprint.contains("="))
    }

    func testByteArrayAndDataAgree() {
        let bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        XCTAssertEqual(
            HostKeyFingerprint.sha256(ofPublicKeyBlob: bytes),
            HostKeyFingerprint.sha256(ofPublicKeyBlob: Data(bytes))
        )
    }
}
