# Security model

GlassSSH is designed so that **secret material never leaves the device and is never
transported in a link or QR code.** This document records the threat-model notes
behind that design and points at the code that enforces each property.

## Summary of properties

| Property | Mechanism | Enforced in |
| --- | --- | --- |
| Private keys are non-exportable | Secure Enclave P-256 keys; signing happens inside the Enclave | `Security` subsystem (app) |
| Passwords are not stored in profiles | Keychain storage, referenced indirectly | `CredentialManaging`, `ConnectionProfile` |
| Host keys can't be silently swapped | Trust-on-first-use pinning with mismatch detection | `KnownHostsStore` |
| QR codes / deep links carry no secrets | Codecs have no field for secret material | `ProfileQRCodec`, `PairingPayload` |

## Secure Enclave P-256 keys

Public-key authentication is backed by the Secure Enclave (P-256 / ECDSA). The
`Security` subsystem generates keys in the Enclave and exposes only metadata
through `ManagedKey` (`App/GlassSSH/App/AppInterfaces.swift`):

```swift
public struct ManagedKey {
    public var id: String                 // Secure Enclave / Keychain reference tag
    public var label: String
    public var openSSHPublicKey: String   // PUBLIC key only
    public var createdAt: Date
}
```

- The **private key is non-exportable**: it lives in the Enclave and there is no
  API on `ManagedKey` (or anywhere else) to read raw private bytes.
- Signing is performed inside the Enclave. When a connection needs public-key
  auth, the signer materializes a `NIOSSHPrivateKey` that delegates signing to the
  Enclave; `SSHClient` consumes it as `SSHCredentials.Method.privateKey`
  (`Core/Sources/GlassSSHNet/SSHClient.swift`) and never persists it.
- Keys are referenced from a `ConnectionProfile` only by tag
  (`keyReference` / `ManagedKey.id`), never by value.

**Threat addressed:** device compromise / backup exfiltration cannot yield a
usable private key, because the bytes are not present outside the Enclave.

## Keychain password storage

Per-profile passwords are stored in the Keychain via `CredentialManaging`:

```swift
func savePassword(_ password: String, for profileID: UUID) throws
func password(for profileID: UUID) -> String?
```

The entitlements scope a single keychain access group
(`App/GlassSSH/GlassSSH.entitlements`):
`$(AppIdentifierPrefix)com.darrylbradshaw.glassssh`.

`ConnectionProfile` (`Core/Sources/GlassSSHCore/ConnectionProfile.swift`) is
**pure metadata** — it has no password field at all, so a serialized profile (in
storage, in a backup, or in a `glassssh://` URL) can never contain one. At connect
time the app fetches the password from the Keychain and wraps it as
`SSHCredentials.Method.password`, which `SSHClient` uses for the single auth offer
and discards.

**Threat addressed:** passwords are not embedded in shareable artifacts and are
protected by the Keychain's at-rest encryption and access control.

## TOFU host-key pinning

`KnownHostsStore` (`Core/Sources/GlassSSHCore/KnownHostsStore.swift`) implements
trust-on-first-use pinning of OpenSSH `SHA256:` fingerprints, computed by
`HostKeyFingerprint.sha256(ofPublicKeyBlob:)` over the raw public-key blob — the
same bytes OpenSSH hashes.

Key safety property: **existing pins are never silently overwritten.**

- `evaluate(host:port:fingerprint:)` returns `.trusted`, `.unknown`, or
  `.mismatch(expected:actual:)`.
- `trustOnFirstUse(...)` records a fingerprint **only when the host is unknown**.
  If a different key is already pinned it returns `.mismatch` and leaves the stored
  pin untouched.
- Replacing a pin requires an explicit `pin(...)` call, which the app makes only
  after the user knowingly accepts a changed key.

Lookup keys are canonicalized like OpenSSH `known_hosts` (host lowercased, default
port normalized away, non-default ports written as `[host]:port`), so the same
host can't be tracked under two inconsistent entries.

During the SSH handshake, `ValidatingHostKeyDelegate`
(`Core/Sources/GlassSSHNet/SSHClient.swift`) routes the server's key through the
app's validator closure, which consults the store and returns `.accept` /
`.reject`; a `.reject` fails the connection with `SSHClientError.hostKeyRejected`.

**Threat addressed:** man-in-the-middle / host-key substitution. A swapped key
surfaces as a `.mismatch` and blocks the connection instead of being trusted.

## QR codes carry no secrets

Both `glassssh://` actions are decoded from QR codes or deep links, and **neither
can carry secret material** — by construction, not just by convention:

- `glassssh://connect` encodes a `ConnectionProfile`, which has no secret field.
  Its `key` parameter is a Keychain/Enclave **reference tag**, and `fp` is a public
  host-key fingerprint to pin. (`ProfileQRCodec`.)
- `glassssh://pair` encodes a `PairingPayload`: host/port/service, the public host
  fingerprint to pin, and a **one-time, short-lived token**. The token
  authenticates the pairing handshake, not the SSH session; it is not a reusable
  credential, and pairing QRs expire (`PairingPayload.isExpired(asOf:)`).
  (`PairingPayload` / `PairingCodec`.)

See [URL-SCHEME.md](URL-SCHEME.md) for the full field reference and the no-secrets
policy, and [PAIRING.md](PAIRING.md) for how pinning happens during pairing.

**Threat addressed:** a leaked, photographed, or intercepted QR/link cannot reveal
a password or private key, and a leaked pairing token is time-bounded and
single-use.

## Out of scope / assumptions

- The pairing companion is assumed to run on a host the operator trusts; it reads
  the local host key to publish its fingerprint.
- GlassSSH does not implement its own crypto primitives — it relies on swift-crypto
  (`Crypto.SHA256`), SwiftNIO-SSH, and the platform Secure Enclave / Keychain.
- Network confidentiality and integrity are provided by the SSH transport itself;
  GlassSSH's responsibility is correct host-key verification and secret handling.
</content>
