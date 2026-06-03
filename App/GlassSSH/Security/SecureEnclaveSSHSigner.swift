import Foundation
import CryptoKit
import GlassSSHCore
import GlassSSHNet
import NIOSSH

/// Bridges a Secure-Enclave-backed P-256 key into a `NIOSSHPrivateKey` so it can
/// be used for SSH `publickey` authentication via ``SSHClient``.
///
/// ## How the bridge works
/// swift-nio-ssh accepts a Secure Enclave key directly through
/// `NIOSSHPrivateKey(secureEnclaveP256Key:)`, which takes swift-crypto's
/// `SecureEnclave.P256.Signing.PrivateKey`. That swift-crypto type *is* the
/// supported "custom key" path on Apple platforms: every signature is computed
/// inside the enclave (NIOSSH calls the key's `signature(for:)`, which routes to
/// `SecKeyCreateSignature` with `.ecdsaSignatureMessageX962SHA256`), and the
/// resulting DER signature is repackaged by NIOSSH into the SSH
/// `ecdsa-sha2-nistp256` `NIOSSHSignature` wire format. The private key never
/// leaves the hardware.
///
/// > Note: swift-nio-ssh does **not** expose a generic public custom-signer
/// > protocol (no public `NIOSSHSigningKey`/`NIOSSHPrivateKeyProtocol`); the
/// > Secure Enclave initializer is the sanctioned integration point. We therefore
/// > build on it rather than hand-rolling raw signature bytes. See
/// > ``makeNIOSSHPrivateKey(from:)`` for the single line that depends on the
/// > NIOSSH version.
///
/// ## Secure Enclave constraints
/// Only NIST **P-256** keys are supported by the enclave, and the private key is
/// non-exportable. See ``SecureEnclaveKey`` for the full rationale.
@MainActor
public struct SecureEnclaveSSHSigner {

    public enum Failure: Error, CustomStringConvertible {
        case unsupportedPlatform

        public var description: String {
            switch self {
            case .unsupportedPlatform:
                return "Secure Enclave SSH signing is only available on Apple platforms."
            }
        }
    }

    private let keyStore: KeyStore

    public init(keyStore: KeyStore) {
        self.keyStore = keyStore
    }

    /// Loads the enclave key for the given ``ManagedKey/id`` reference and returns
    /// a `NIOSSHPrivateKey` ready to drop into `SSHCredentials.Method.privateKey`.
    ///
    /// All signing performed with the returned key happens inside the Secure
    /// Enclave; no private material is ever materialized in app memory.
    public func makePrivateKey(reference: String) throws -> NIOSSHPrivateKey {
        let enclaveKey = try keyStore.loadSigningKey(reference: reference)
        return try Self.makeNIOSSHPrivateKey(from: enclaveKey)
    }

    /// Convenience: build `SSHCredentials` for publickey auth in one step.
    public func credentials(username: String, reference: String) throws -> SSHCredentials {
        let key = try makePrivateKey(reference: reference)
        return SSHCredentials(username: username, method: .privateKey(key))
    }

    /// The one NIOSSH-version-sensitive call. Isolated so that if the custom-key
    /// API changes, only this helper needs updating.
    ///
    // VERIFY: NIOSSH custom-key API.
    // As of swift-nio-ssh (>= 0.9.x, current `main`) the Darwin-only initializer
    // `NIOSSHPrivateKey(secureEnclaveP256Key:)` is the supported bridge for
    // Secure Enclave keys. It is guarded by `#if canImport(Darwin)` in NIOSSH, so
    // we guard the call the same way. If a future NIOSSH renames/removes it, this
    // is the only place to change.
    static func makeNIOSSHPrivateKey(
        from enclaveKey: SecureEnclave.P256.Signing.PrivateKey
    ) throws -> NIOSSHPrivateKey {
        #if canImport(Darwin)
        return NIOSSHPrivateKey(secureEnclaveP256Key: enclaveKey)
        #else
        throw Failure.unsupportedPlatform
        #endif
    }
}
