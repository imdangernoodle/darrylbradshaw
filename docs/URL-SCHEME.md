# The `glassssh://` URL scheme

GlassSSH uses a single custom URL scheme, `glassssh`, with two actions encoded as
the URL host:

- **`glassssh://connect`** — import a connection profile (typically from a
  `glassssh://connect` QR code).
- **`glassssh://pair`** — pair via the Bonjour companion: import a profile **and**
  pin a host-key fingerprint (typically a short-lived QR shown by the companion).

Both are decoded in `AppModel.handleIncomingURL(_:)`, which is invoked from
`GlassSSHApp.onOpenURL` when a QR is scanned or a universal link is opened.

The canonical encoders/decoders are in `Core/Sources/GlassSSHCore`:
`ProfileQRCodec` (connect) and `PairingCodec` / `PairingPayload` (pair). This
document mirrors that code exactly.

## No-secrets policy

> **A `glassssh://` URL never carries a password or private key.**

It carries only connection metadata plus the host-key fingerprint to pin (and, for
pairing, a one-time token). Passwords are entered on-device and stored in the
Keychain; private keys are generated in and never leave the Secure Enclave. The
`key` field is a Keychain/Secure Enclave **reference tag**, not key material. See
[SECURITY.md](SECURITY.md).

This is enforced structurally: `ConnectionProfile` and `PairingPayload` have no
field that can hold secret material, so the codecs cannot emit one.

---

## `glassssh://connect`

Imports a `ConnectionProfile`. Produced by `ProfileQRCodec.makeURL(from:)` and
parsed by `ProfileQRCodec.profile(from:)`.

### Fields

| Query key | Required | Maps to | Notes |
| --- | --- | --- | --- |
| `host` | **yes** | `host` | Hostname or IP. Decoding throws `missingField("host")` if absent/empty. |
| `user` | **yes** | `username` | Decoding throws `missingField("user")` if absent/empty. |
| `port` | no | `port` | Integer in `1...65535`. Defaults to `22` (`ConnectionProfile.defaultPort`). An out-of-range or non-numeric value throws `invalidPort`. |
| `name` | no | `name` | Display label. Defaults to the value of `host` when absent/empty. |
| `auth` | no | `authMethod` | `password` or `publicKey`. Any other/missing value falls back to `password`. |
| `key` | no | `keyReference` | Keychain / Secure Enclave **tag** for the key used with `publicKey` auth. Never key material. Omitted when `nil`. |
| `fp` | no | `pinnedHostFingerprint` | OpenSSH `SHA256:...` host-key fingerprint to pin. Omitted when `nil`. |

> Note: the encoder always writes `host`, `port`, `user`, `name`, and `auth`; `fp`
> and `key` are written only when present. The decoder treats `port`, `name`,
> `auth`, `key`, and `fp` as optional with the defaults above.

### Examples

```
# Password destination, custom port, with a host-key fingerprint to pin
glassssh://connect?host=example.com&port=2222&user=alice&name=Prod&auth=password&fp=SHA256:abcd1234...

# Public-key destination referencing a Secure Enclave key by tag
glassssh://connect?host=10.0.0.5&user=ops&name=Build%20Box&auth=publicKey&key=com.darrylbradshaw.glassssh.key.build

# Minimal: only the two required fields (defaults: port 22, name=host, auth=password)
glassssh://connect?host=server.lan&user=root
```

---

## `glassssh://pair`

Imports a `PairingPayload` (which can be converted to a `ConnectionProfile` via
`makeProfile()`). Produced by `PairingCodec.makeURL(from:)` and parsed by
`PairingCodec.payload(from:)`. Used by the Bonjour companion; see
[PAIRING.md](PAIRING.md).

### Fields

| Query key | Required | Maps to | Notes |
| --- | --- | --- | --- |
| `host` | **yes** | `host` | Throws `missingField("host")` if absent/empty. |
| `service` | **yes** | `serviceName` | Bonjour service instance name the companion advertises. Also used as the imported profile's `name`. Throws `missingField("service")` if absent. |
| `fp` | **yes** | `hostFingerprint` | OpenSSH `SHA256:...` fingerprint to pin (TOFU). Throws `missingField("fp")` if absent. |
| `token` | **yes** | `token` | One-time pairing token the companion can verify on first connect. Throws `missingField("token")` if absent. |
| `port` | no | `port` | Integer in `1...65535`. Defaults to `22`. Bad values throw `invalidPort`. |
| `user` | no | `username` | Optional. Stays `nil` when absent/empty. |
| `exp` | no | `expiresAt` | Expiry as a Unix epoch (seconds). Parsed via `Int`; ignored if non-numeric. Pairing QRs are short-lived by design (`PairingPayload.isExpired(asOf:)`). |

> The token is a **one-time verification handle**, not a secret credential — it
> authenticates the *pairing handshake*, not the SSH session. SSH auth still uses
> a Keychain password or Secure Enclave key.

### Profile produced by `makeProfile()`

`PairingPayload.makeProfile()` builds:

- `name` = `serviceName`
- `host`, `port` = as decoded
- `username` = `username ?? ""`
- `authMethod` = `.password`
- `pinnedHostFingerprint` = `hostFingerprint`

### Examples

```
# Full pairing QR with expiry
glassssh://pair?host=10.0.0.5&port=22&service=studio-mac&fp=SHA256:abcd1234...&token=9f3a-one-time&exp=1717459200

# With a suggested username, no expiry
glassssh://pair?host=192.168.1.42&service=ci-runner&user=deploy&fp=SHA256:wxyz...&token=8b2c-one-time
```

---

## Error handling

Both decoders throw `QRCodecError` (`Core/Sources/GlassSSHCore/ProfileQRCodec.swift`):

| Case | When |
| --- | --- |
| `invalidURL` | The string is not a parseable URL / `URLComponents`. |
| `wrongScheme(String?)` | The scheme is not `glassssh`. |
| `unknownAction(String?)` | The host is not `connect` (for `ProfileQRCodec`) or `pair` (for `PairingCodec`). |
| `missingField(String)` | A required field is absent or empty. |
| `invalidPort(String)` | `port` is non-numeric or outside `1...65535`. |

`AppModel.handleIncomingURL(_:)` tries `ProfileQRCodec.profile(from:)` first and
falls back to `PairingCodec.payload(from:)`, so any thrown error simply means the
URL is ignored (no import sheet is presented).
</content>
