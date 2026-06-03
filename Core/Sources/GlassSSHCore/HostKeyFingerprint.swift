import Foundation
import Crypto

/// Computes OpenSSH-style host-key fingerprints (`SHA256:base64-no-padding`).
///
/// The input is the raw SSH public-key blob (the wire-format key bytes), which is
/// exactly what OpenSSH hashes when it prints `SHA256:...` fingerprints. The app
/// layer is responsible for obtaining those bytes from a `NIOSSHPublicKey`.
public enum HostKeyFingerprint {
    public static func sha256(ofPublicKeyBlob blob: Data) -> String {
        let digest = SHA256.hash(data: blob)
        let base64 = Data(digest).base64EncodedString()
        let noPadding = base64.replacingOccurrences(of: "=", with: "")
        return "SHA256:\(noPadding)"
    }

    public static func sha256(ofPublicKeyBlob bytes: [UInt8]) -> String {
        sha256(ofPublicKeyBlob: Data(bytes))
    }
}
