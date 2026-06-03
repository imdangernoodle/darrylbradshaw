# GlassSSH

A **Liquid Glass SSH client for iPad Pro** — a native iPadOS 26 app with a
hardware-accelerated terminal, Bonjour discovery, and QR-based connection import
and pairing.

> Working name. Easy to rename later.

## What it will do

- **Liquid Glass UI** — SwiftUI `glassEffect` / `GlassEffectContainer` sidebar and
  floating terminal toolbar (iPadOS 26+).
- **Hardware-accelerated terminal** — [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
  with its Metal GPU renderer (glyph atlas + instanced draws).
- **Real SSH** — [apple/swift-nio-ssh](https://github.com/apple/swift-nio-ssh),
  password + Secure-Enclave public-key auth.
- **Bonjour discovery** — `NWBrowser` surfaces `_ssh._tcp` and a custom
  `_glasspair._tcp` on the LAN.
- **QR, two ways** — scan a `glassssh://connect` code to import a destination, or
  scan the `glassssh://pair` code from the Bonjour companion to pin the host key
  (trust-on-first-use) and one-tap connect.

## Architecture

```
darrylbradshaw/
├─ Core/        GlassSSHCore — platform-agnostic logic (this is what CI builds & tests on Linux)
├─ App/         GlassSSH.xcodeproj — the iPadOS 26 app (SwiftUI + SwiftTerm + Keychain)   [later phases]
├─ Companion/   glasspair — Bonjour advertiser + pairing-QR generator                      [later phases]
└─ .github/     CI: builds and tests Core in the official Swift container
```

The terminal, Keychain/Secure Enclave, and Liquid Glass UI require macOS + Xcode 26
to build, so they can't be compiled in Linux CI. As much logic as possible lives in
`Core/` precisely so it *is* CI-verified.

## Build status by phase

- [x] **Phase 1 — Core (Linux-verifiable):** connection profiles, `glassssh://`
      QR codec (connect + pair), trust-on-first-use known-hosts store, OpenSSH
      SHA-256 fingerprints, and the async SwiftNIO-SSH client (connect / auth /
      PTY shell / resize). Unit-tested in CI.
- [ ] Phase 2 — Xcode app shell + SwiftTerm terminal (Metal renderer)
- [ ] Phase 3 — Auth & Secure Enclave key signing
- [ ] Phase 4 — Bonjour discovery
- [ ] Phase 5 — QR (import + pairing) + companion
- [ ] Phase 6 — Liquid Glass polish
- [ ] Phase 7 — Docs & release

## Core package

The `GlassSSHCore` Swift package builds and tests on Linux and macOS:

```bash
cd Core
swift build
swift test
```

### `glassssh://` URL format

```
# Import a connection profile
glassssh://connect?host=example.com&port=2222&user=alice&name=Prod&auth=publicKey&fp=SHA256:...&key=<keychain-tag>

# Pair via the Bonjour companion (short-lived)
glassssh://pair?host=10.0.0.5&port=22&service=studio-mac&fp=SHA256:...&token=<one-time>&exp=<epoch>
```

QR codes carry **no secrets** — only connection metadata and the host-key
fingerprint to pin. Passwords and private keys stay on the device.
