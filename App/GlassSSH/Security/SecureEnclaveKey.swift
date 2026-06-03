import Foundation
// On Apple platforms swift-crypto's `Crypto.SecureEnclave`/`P256` are re-exported
// type aliases for the system `CryptoKit` types, so importing CryptoKit here
// yields the exact types `NIOSSHPrivateKey(secureEnclaveP256Key:)` expects — and
// avoids needing a direct swift-crypto package dependency on the app target.
import CryptoKit

#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Low-level helpers for creating and reloading Secure Enclave P-256 signing keys
/// and exporting them in OpenSSH wire format.
///
/// ## Secure Enclave constraints
/// The Secure Enclave only supports **NIST P-256 (`secp256r1`)** keys for ECDSA
/// signing. No other curve (P-384, P-521, Ed25519, RSA) can be generated inside
/// the enclave. The private key material **never leaves the enclave**: what we
/// persist is an opaque, enclave-bound *key blob* (`dataRepresentation`) that is
/// useless on any other device and cannot be turned back into raw private bytes.
/// All signing happens inside the enclave hardware.
///
/// We use swift-crypto's `SecureEnclave.P256.Signing.PrivateKey`, which wraps
/// `SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave` and a
/// `SecAccessControl` under the hood. Using the swift-crypto type (rather than a
/// bare `SecKey`) is what lets us hand the key to swift-nio-ssh via
/// `NIOSSHPrivateKey(secureEnclaveP256Key:)` — see ``SecureEnclaveSSHSigner``.
enum SecureEnclaveKey {
    enum Failure: Error, CustomStringConvertible {
        case secureEnclaveUnavailable
        case accessControlCreationFailed(String)
        case keyGenerationFailed(String)
        case keyLoadFailed(String)

        var description: String {
            switch self {
            case .secureEnclaveUnavailable:
                return "The Secure Enclave is not available on this device."
            case .accessControlCreationFailed(let message):
                return "Failed to create Secure Enclave access control: \(message)"
            case .keyGenerationFailed(let message):
                return "Failed to generate Secure Enclave key: \(message)"
            case .keyLoadFailed(let message):
                return "Failed to load Secure Enclave key: \(message)"
            }
        }
    }

    /// Whether this device exposes a usable Secure Enclave.
    ///
    /// On the simulator this reflects the emulated enclave (available on recent
    /// Xcode/OS combinations); callers should treat the result as best-effort.
    static var isAvailable: Bool {
        SecureEnclave.isAvailable
    }

    /// Generates a fresh, non-exportable P-256 signing key inside the Secure
    /// Enclave and returns its persistable, enclave-bound key blob.
    ///
    /// The returned `dataRepresentation` is *not* the private key — it is an
    /// encrypted reference that only this device's enclave can unwrap. Persist it
    /// (we store it in the Keychain in ``KeyStore``) and reload it later via
    /// ``loadKey(blob:)``.
    static func generateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard isAvailable else { throw Failure.secureEnclaveUnavailable }

        let access = try makeAccessControl()
        do {
            return try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        } catch {
            throw Failure.keyGenerationFailed(String(describing: error))
        }
    }

    /// Reloads a previously generated enclave key from its persisted blob.
    static func loadKey(blob: Data) throws -> SecureEnclave.P256.Signing.PrivateKey {
        do {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
        } catch {
            throw Failure.keyLoadFailed(String(describing: error))
        }
    }

    /// Builds the access-control policy applied to the enclave key.
    ///
    /// `.privateKeyUsage` permits signing; `.afterFirstUnlock` keeps the key
    /// usable once the device has been unlocked at least once after boot. We
    /// deliberately avoid `.userPresence`/biometry here so background SSH
    /// reconnects don't prompt; callers wanting biometric gating can supply an
    /// `LAContext` at sign time in a future revision.
    private static func makeAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.privateKeyUsage],
            &error
        ) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown error"
            throw Failure.accessControlCreationFailed(message)
        }
        return access
    }
}

// MARK: - OpenSSH public-key export

extension P256.Signing.PublicKey {
    /// Encodes this P-256 public key as an OpenSSH `authorized_keys` line.
    ///
    /// The format is the SSH `ecdsa-sha2-nistp256` wire encoding, base64'd, with a
    /// trailing comment:
    ///
    /// ```
    /// ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAI...== <comment>
    /// ```
    ///
    /// The wire blob is three SSH `string` fields (RFC 4253 / RFC 5656):
    /// 1. the key-type name `"ecdsa-sha2-nistp256"`,
    /// 2. the curve identifier `"nistp256"`,
    /// 3. the 65-byte uncompressed EC point `0x04 || X || Y` (the X9.63 form).
    func openSSHAuthorizedKey(comment: String) -> String {
        let keyType = "ecdsa-sha2-nistp256"
        let curveName = "nistp256"
        // `x963Representation` is exactly the 65-byte uncompressed point
        // (0x04 prefix + 32-byte X + 32-byte Y) the SSH format requires.
        let point = self.x963Representation

        var blob = Data()
        blob.appendSSHString(Data(keyType.utf8))
        blob.appendSSHString(Data(curveName.utf8))
        blob.appendSSHString(point)

        let base64 = blob.base64EncodedString()
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedComment.isEmpty {
            return "\(keyType) \(base64)"
        }
        return "\(keyType) \(base64) \(trimmedComment)"
    }
}

private extension Data {
    /// Appends an SSH `string`: a 4-byte big-endian length prefix followed by the
    /// raw bytes (RFC 4251 §5).
    mutating func appendSSHString(_ payload: Data) {
        var length = UInt32(payload.count).bigEndian
        Swift.withUnsafeBytes(of: &length) { append(contentsOf: $0) }
        append(payload)
    }
}
