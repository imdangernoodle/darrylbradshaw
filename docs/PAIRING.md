# Pairing & discovery

GlassSSH can add a destination three ways: by hand, by scanning a
`glassssh://connect` QR, or by **pairing** with a host through the Bonjour
companion. Pairing is the smoothest path because it also pins the host key, so the
very first connection is already verified.

## Bonjour discovery

The app's `Bonjour` subsystem (the `HostDiscovering` protocol in
`App/GlassSSH/App/AppInterfaces.swift`) runs an `NWBrowser` and surfaces
`DiscoveredHost` values for two service types:

| Service | `DiscoveredHost.Kind` | Meaning |
| --- | --- | --- |
| `_ssh._tcp` | `.ssh` | A standard SSH server advertising over Bonjour. |
| `_glasspair._tcp` | `.pairing` | A GlassSSH pairing companion offering a one-tap pair. |

Both are declared in the app's `Info.plist` (`NSBonjourServices`) via
`App/project.yml`, alongside the `NSLocalNetworkUsageDescription` prompt. Discovered
hosts appear in the Connections sidebar next to saved profiles.

Discovering an `_ssh._tcp` host lets you pre-fill host/port for a new profile, but
its host key is still unknown until first connect. Discovering a `_glasspair._tcp`
companion lets you pair, which also pins the key up front.

## QR + pairing flow

```
  Companion (desktop)                         iPad (GlassSSH)
  ─────────────────────                       ─────────────────
  1. Advertise _glasspair._tcp  ───Bonjour──►  appears as a .pairing host
  2. Read server host key
     compute SHA256: fingerprint
  3. Print glassssh://pair QR
     (host, port, service, fp,    ───scan────►  4. PairingCodec.payload(from:)
      token, optional exp)                          decodes the URL
                                                 5. payload.makeProfile() →
                                                    ConnectionProfile
                                                 6. KnownHostsStore TOFU-pins fp
                                                 7. user connects → host key
                                                    matches the pinned fp ⇒ .trusted
```

1. **Companion advertises** itself over Bonjour as `_glasspair._tcp` and reads the
   local SSH server's host key.
2. **Companion prints a QR** encoding a `glassssh://pair` URL. Its fields
   (`host`, `port`, `service`, `fp`, `token`, optional `exp`) are specified in
   [URL-SCHEME.md](URL-SCHEME.md). The `fp` is the OpenSSH `SHA256:` fingerprint
   of the host key; the `token` is a one-time pairing handle; pairing QRs are
   short-lived (`exp`).
3. **iPad scans** the code. `GlassSSHApp.onOpenURL` → `AppModel.handleIncomingURL`
   decodes it with `PairingCodec.payload(from:)`.
4. **A profile is created** via `PairingPayload.makeProfile()` and presented for
   import (`pendingImport`); the `Data` subsystem persists it.
5. **The fingerprint is pinned** in the `KnownHostsStore` (trust-on-first-use).
6. **First connect verifies** against that pin: because the server presents the
   same key, `KnownHostsStore.evaluate` returns `.trusted` and the connection
   proceeds without a scary unknown-host prompt.

## Trust-on-first-use (TOFU) host keys

Host-key trust lives in `Core/Sources/GlassSSHCore/KnownHostsStore.swift`. It maps
a canonical `host[:port]` key to a pinned OpenSSH `SHA256:` fingerprint and backs
onto a pluggable `KnownHostsPersistence` (in-memory in tests; file/Keychain in the
app).

Canonical keys mirror OpenSSH's `known_hosts`: the default port is normalized away,
and the host is lowercased — so `Example.com` and `example.com:22` collapse to the
same entry, while a non-default port becomes `[host]:port`.

`evaluate(host:port:fingerprint:)` returns one of:

| Decision | Meaning | Typical UI |
| --- | --- | --- |
| `.trusted` | The presented key matches the pinned one. | Connect silently. |
| `.unknown` | No pin exists yet (first contact). | TOFU-pin (or prompt to accept). |
| `.mismatch(expected:actual:)` | A pin exists but the key changed. | **Warn and block** until the user explicitly re-pins. |

Two write paths exist:

- **`trustOnFirstUse(host:port:fingerprint:)`** records the fingerprint **only if
  the host is currently unknown**, then returns `.trusted`. If a different key is
  already pinned it returns `.mismatch` and **does not** overwrite. This is the key
  safety property: a changed host key never gets silently accepted.
- **`pin(host:port:fingerprint:)`** explicitly replaces the pin — used only when
  the user deliberately accepts a changed key.

Pairing pre-seeds the pin from the companion's `fp`, so the first real connection
takes the `.trusted` path rather than `.unknown`.

## Running the companion

The companion lives in `Companion/` (referenced in the code as
`Companion/glasspair.py`). It is being added in parallel; the companion's own
README is the authoritative runbook. At a high level:

1. Run the companion on a machine that can reach the SSH server (commonly the
   server itself).
2. It advertises `_glasspair._tcp` over Bonjour and prints a `glassssh://pair` QR.
3. Open GlassSSH on the iPad, scan the QR (or tap the discovered `.pairing` host),
   and confirm the import.
4. Connect. The host key is already pinned, so the session is trusted on first
   use.

Because the pairing QR is short-lived and the token is one-time, regenerate it if
it expires before you scan.
</content>
