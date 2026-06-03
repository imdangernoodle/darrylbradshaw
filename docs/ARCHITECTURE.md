# Architecture

GlassSSH is split into three top-level components: a platform-agnostic Swift
package (`Core/`), the iPadOS app (`App/`), and a desktop pairing helper
(`Companion/`). The split exists so that as much logic as possible is unit-tested
in Linux CI, while only the genuinely platform-bound pieces (terminal rendering,
Secure Enclave, Keychain, Liquid Glass UI) live in the Xcode target.

```
┌──────────────────────────────────────────────────────────────┐
│  App/  (iPadOS 26, SwiftUI + SwiftTerm + Keychain/Enclave)     │
│                                                                │
│   Theme · Terminal · Security · Bonjour · QR · Data · UI       │
│        │            │           │                              │
│        └────────────┴───────────┴──────────────┐              │
│                          depends on             ▼              │
├──────────────────────────────────────────────────────────────┤
│  Core/  (pure Swift, CI-tested on Linux & macOS)               │
│                                                                │
│   GlassSSHCore  ──────────────►  GlassSSHNet                   │
│   profiles, codecs, TOFU store   SwiftNIO-SSH client           │
└──────────────────────────────────────────────────────────────┘

      ▲ scans glassssh://pair QR        advertises Bonjour + prints QR ▲
      └──────────────────────────  Companion/  ───────────────────────┘
```

## Module map

### `Core/` — `GlassSSHCore` + `GlassSSHNet`

Two SwiftPM library products defined in `Core/Package.swift`.

#### `GlassSSHCore` (no networking; depends only on swift-crypto)

| File | Responsibility |
| --- | --- |
| `ConnectionProfile.swift` | The saved-destination value type. Pure metadata — **never** holds a password or private key; key material is referenced indirectly via `keyReference`. Default port `22`, `AuthMethod` of `.password` / `.publicKey`, plus `displayDestination` / `isValid` helpers. |
| `ProfileQRCodec.swift` | Encodes/decodes a `ConnectionProfile` to/from a `glassssh://connect?...` URL for QR import. Also defines `QRCodecError` and the shared `QueryDecoding` helpers. |
| `PairingPayload.swift` | The `glassssh://pair` payload (`PairingPayload`) and its codec (`PairingCodec`). Carries host/port/service/fingerprint/token plus an optional expiry; `makeProfile()` turns a payload into an importable `ConnectionProfile`. |
| `HostKeyFingerprint.swift` | Computes OpenSSH-style `SHA256:base64-no-padding` fingerprints from a raw public-key blob. |
| `KnownHostsStore.swift` | Trust-on-first-use known-hosts store mapping `host[:port]` → pinned fingerprint. Pluggable `KnownHostsPersistence` (in-memory for tests; file/Keychain in the app). Existing entries are never silently overwritten. |

#### `GlassSSHNet` (depends on `GlassSSHCore` + SwiftNIO + NIOSSH)

| File | Responsibility |
| --- | --- |
| `SSHClient.swift` | Thin async wrapper around SwiftNIO-SSH: `connect` (with auth + host-key validation), `startShell` (PTY + interactive shell), and `disconnect`. Exposes a `ShellSession` whose `output` is an `AsyncThrowingStream<Data, Error>` and whose `send` / `sendText` / `resize` push input and window-change events back. Internally wires `CredentialAuthDelegate`, `ValidatingHostKeyDelegate`, and `ShellChannelHandler`. |

`Core/` is what `.github/workflows/ci.yml` builds and tests in the official Swift
container.

### `App/` — `GlassSSH` (iPadOS 26)

Generated from `App/project.yml` via XcodeGen (see `App/BUILD.md`). The target
depends on the `SwiftTerm` package and on both `GlassSSHCore` and `GlassSSHNet`
from the local `Core` package. The source tree is organized into subsystems:

| Subsystem (`App/GlassSSH/…`) | Responsibility |
| --- | --- |
| `App/` | `@main` entry (`GlassSSHApp`), the `AppModel` coordinator, the `RootView` scaffold, and the protocol interfaces (`AppInterfaces.swift`) the other subsystems implement. |
| `Theme/` | Liquid Glass design system (glass materials, colors, typography). |
| `Terminal/` | SwiftTerm view + Metal renderer + the bridge to `GlassSSHNet`'s `ShellSession`. |
| `Security/` | Secure Enclave P-256 key generation/signing, Keychain password storage, and the NIOSSH signer that produces a `NIOSSHPrivateKey` for public-key auth. |
| `Bonjour/` | `NWBrowser`-based discovery of `_ssh._tcp` and `_glasspair._tcp`. |
| `QR/` | Camera scanning, QR generation, and routing of incoming `glassssh://` URLs. |
| `Data/` | Persistence for profiles, settings, and the file/Keychain-backed `KnownHostsStore`. |
| `UI/` | SwiftUI screens — Connections sidebar, Terminal screen, Settings. |
| `Resources/` | Asset catalog. |

The current `App/` tree contains the Phase-2 scaffold: `App/`, `Resources/`, the
entitlements, and `project.yml`. The remaining subsystem folders are populated by
the parallel work units; the protocols in `AppInterfaces.swift` are the contract
between them.

### `Companion/` — `glasspair`

A desktop helper (referenced from the code as `Companion/glasspair.py`) that
advertises a host over Bonjour as `_glasspair._tcp` and prints a `glassssh://pair`
QR code. The iPad scans it to pin the host key (TOFU) and connect with one tap.
See [PAIRING.md](PAIRING.md).

## Connection data flow

A full connection moves through four stages. Stages 1–2 are optional shortcuts;
you can also add a profile by hand.

### 1. Discover (optional)

`Bonjour` (`HostDiscovering`) runs an `NWBrowser` and publishes `DiscoveredHost`
values. Each has a `Kind` of `.ssh` (`_ssh._tcp`) or `.pairing`
(`_glasspair._tcp`). The Connections UI lists them alongside saved profiles.

### 2. Import / pair (optional)

- **Import:** scanning a `glassssh://connect` QR (or opening a universal link)
  reaches `GlassSSHApp.onOpenURL` → `AppModel.handleIncomingURL`, which calls
  `ProfileQRCodec.profile(from:)` and sets `pendingImport` to present an import
  sheet.
- **Pair:** scanning a `glassssh://pair` QR from the companion is decoded by
  `PairingCodec.payload(from:)`; `PairingPayload.makeProfile()` produces the
  importable `ConnectionProfile`, again surfaced via `pendingImport`. The
  payload's `hostFingerprint` is the value pinned in stage 4.

Both paths produce a `ConnectionProfile`, persisted by the `Data` subsystem
(`ProfileStoring`). No secrets arrive over the QR — see [URL-SCHEME.md](URL-SCHEME.md).

### 3. Authenticate

When the user connects, the `Security` subsystem (`CredentialManaging`) resolves
credentials:

- **Password** — fetched from the Keychain (`password(for:)`), wrapped as
  `SSHCredentials(method: .password(...))`.
- **Public key** — the Secure-Enclave-backed signer materializes a
  `NIOSSHPrivateKey`, wrapped as `SSHCredentials(method: .privateKey(...))`.

`SSHClient.connect(host:port:credentials:hostKeyValidator:)` runs the TCP +
SSH handshake. The `hostKeyValidator` closure receives the server's
`NIOSSHPublicKey`; the app computes its `SHA256:` fingerprint
(`HostKeyFingerprint.sha256(ofPublicKeyBlob:)`) and consults the
`KnownHostsStore`:

- `.trusted` (matches a pinned key) → accept.
- `.unknown` (first contact) → trust-on-first-use, pin and accept; or prompt.
- `.mismatch(expected:actual:)` → reject unless the user explicitly re-pins.

`CredentialAuthDelegate` offers exactly one credential and gives up rather than
looping; `ValidatingHostKeyDelegate` turns the validator's `.accept` / `.reject`
into the NIOSSH completion promise.

### 4. PTY shell

`SSHClient.startShell(term:cols:rows:)` opens a `.session` child channel.
`ShellChannelHandler` requests a pseudo-terminal and a shell on `handlerAdded`,
forwards inbound `SSHChannelData` out as `Data`, and wraps outbound `ByteBuffer`s
back into `SSHChannelData`. The returned `ShellSession`:

- streams server output via `output` (`AsyncThrowingStream<Data, Error>`),
- accepts keystrokes via `send` / `sendText`,
- forwards terminal resizes via `resize(cols:rows:)`
  (`SSHChannelRequestEvent.WindowChangeRequest`).

The `Terminal` subsystem feeds `output` into SwiftTerm's Metal renderer and pumps
SwiftTerm's input/resize callbacks back into the `ShellSession`.

## Protocol interfaces (`App/GlassSSH/App/AppInterfaces.swift`)

The UI and coordinator depend on protocols, not concrete types, so each work unit
can ship an implementation independently. Final wiring swaps the scaffold's stubs
for the real ones. All are `@MainActor`.

```swift
@MainActor
public protocol ProfileStoring: AnyObject {
    var profiles: [ConnectionProfile] { get }
    func add(_ profile: ConnectionProfile)
    func update(_ profile: ConnectionProfile)
    func remove(_ profile: ConnectionProfile)
    func reload()
}

public struct DiscoveredHost: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable { case ssh; case pairing }   // _ssh._tcp / _glasspair._tcp
    public var id: String
    public var name: String
    public var host: String?
    public var port: Int?
    public var kind: Kind
}

@MainActor
public protocol HostDiscovering: AnyObject {
    var discovered: [DiscoveredHost] { get }
    func start()
    func stop()
}

public struct ManagedKey: Identifiable, Hashable, Sendable {
    public var id: String                 // Keychain / Secure Enclave reference tag
    public var label: String
    public var openSSHPublicKey: String   // public material only
    public var createdAt: Date
}

@MainActor
public protocol CredentialManaging: AnyObject {
    var keys: [ManagedKey] { get }
    func generateKey(label: String) throws -> ManagedKey
    func deleteKey(reference: String) throws
    func savePassword(_ password: String, for profileID: UUID) throws
    func password(for profileID: UUID) -> String?
}
```

The coordinator that ties these together is `AppModel`
(`App/GlassSSH/App/AppModel.swift`): it holds `pendingImport` for deep-link
imports, owns a `KnownHostsStore` (in-memory by default; file-backed once the
`Data` unit lands), and implements `handleIncomingURL(_:)` to route both
`glassssh://connect` and `glassssh://pair` URLs.
</content>
