# GlassSSH

A **Liquid Glass SSH client for iPad Pro** — a native iPadOS 26 app with a
hardware-accelerated terminal, Bonjour discovery, and QR-based connection import
and pairing.

> Working name. Easy to rename later.

GlassSSH pairs a real SwiftNIO-SSH stack with SwiftTerm's Metal renderer and the
new iPadOS 26 Liquid Glass design language. Destinations can be typed in, scanned
from a QR code, or discovered on the LAN via Bonjour. Secrets never leave the
device: passwords live in the Keychain, public-key auth is backed by the Secure
Enclave, and host keys are pinned trust-on-first-use.

## Features

- **Liquid Glass UI** — SwiftUI `glassEffect` / `GlassEffectContainer` sidebar and
  floating terminal toolbar (iPadOS 26+).
- **Hardware-accelerated terminal** — [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
  with its Metal GPU renderer (glyph atlas + instanced draws).
- **Real SSH** — [apple/swift-nio-ssh](https://github.com/apple/swift-nio-ssh):
  connect, authenticate, open a PTY shell, stream output, and handle window
  resize. Password and Secure-Enclave public-key auth.
- **Secure Enclave keys** — P-256 keys generated and used on-device; the private
  key is non-exportable and signing happens inside the Enclave.
- **Bonjour discovery** — `NWBrowser` surfaces `_ssh._tcp` and a custom
  `_glasspair._tcp` on the LAN.
- **QR, two ways** — scan a `glassssh://connect` code to import a destination, or
  scan the `glassssh://pair` code from the Bonjour companion to pin the host key
  (trust-on-first-use) and one-tap connect.
- **Trust-on-first-use host keys** — OpenSSH-style `SHA256:` fingerprints pinned
  per host; a changed key surfaces as a mismatch instead of being silently
  accepted.

## Screenshots

> _Coming soon._ Screenshots of the Liquid Glass sidebar, the terminal screen,
> and the QR pairing flow will be added here once the UI units land.

## Repository layout

```
darrylbradshaw/
├─ Core/        GlassSSHCore + GlassSSHNet — platform-agnostic logic (built & tested on Linux CI)
├─ App/         GlassSSH — the iPadOS 26 app (SwiftUI + SwiftTerm + Keychain), generated with XcodeGen
├─ Companion/   glasspair — Bonjour advertiser + pairing-QR generator
├─ docs/        Architecture, URL scheme, pairing, and security documentation
└─ .github/     CI: builds and tests Core in the official Swift container
```

The terminal, Keychain/Secure Enclave, and Liquid Glass UI require macOS + Xcode 26
to build, so they can't be compiled in Linux CI. As much logic as possible lives in
`Core/` precisely so it *is* CI-verified.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — module map, connection data flow,
  and the App protocol interfaces.
- [docs/URL-SCHEME.md](docs/URL-SCHEME.md) — full `glassssh://connect` and
  `glassssh://pair` URL spec and the no-secrets policy.
- [docs/PAIRING.md](docs/PAIRING.md) — Bonjour + QR pairing flow, TOFU host keys,
  and running the companion.
- [docs/SECURITY.md](docs/SECURITY.md) — threat model: Secure Enclave keys,
  Keychain, host-key pinning, and QR secrecy.

## Quick start

### Core package (Linux or macOS)

`GlassSSHCore` and `GlassSSHNet` build and test without Xcode:

```bash
cd Core
swift build
swift test
```

### iPadOS app

The Xcode project is generated from `App/project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). Full instructions are in
[App/BUILD.md](App/BUILD.md):

```bash
cd App
xcodegen generate
open GlassSSH.xcodeproj
```

Select your development team under **Signing & Capabilities**, then build/run on an
iPad Pro running iPadOS 26 with Xcode 26.

### Companion (pairing helper)

The `Companion/` Bonjour helper advertises a host over the LAN and prints a
`glassssh://pair` QR code so the iPad can pin the host key and connect with one
tap. See [docs/PAIRING.md](docs/PAIRING.md) for how to run it.

## Status & roadmap

- [x] **Phase 1 — Core (Linux-verifiable):** connection profiles, `glassssh://`
      QR codec (connect + pair), trust-on-first-use known-hosts store, OpenSSH
      SHA-256 fingerprints, and the async SwiftNIO-SSH client (connect / auth /
      PTY shell / resize). Unit-tested in CI.
- [x] **Phase 2 — Xcode app shell:** XcodeGen project, `@main` entry, the
      `AppModel` coordinator, deep-link routing, and the protocol interfaces the
      subsystems implement.
- [ ] Phase 3 — SwiftTerm terminal (Metal renderer) + SSH bridge
- [ ] Phase 4 — Auth & Secure Enclave key signing
- [ ] Phase 5 — Bonjour discovery
- [ ] Phase 6 — QR (import + pairing) + companion wiring
- [ ] Phase 7 — Liquid Glass polish
- [ ] Phase 8 — Release

## `glassssh://` URL format

```
# Import a connection profile
glassssh://connect?host=example.com&port=2222&user=alice&name=Prod&auth=publicKey&fp=SHA256:...&key=<keychain-tag>

# Pair via the Bonjour companion (short-lived)
glassssh://pair?host=10.0.0.5&port=22&service=studio-mac&fp=SHA256:...&token=<one-time>&exp=<epoch>
```

QR codes carry **no secrets** — only connection metadata and the host-key
fingerprint to pin. Passwords and private keys stay on the device. The complete
field reference is in [docs/URL-SCHEME.md](docs/URL-SCHEME.md).
</content>
</invoke>
