# GlassSSH Pairing Companion

`glasspair.py` is the desktop/server side of GlassSSH pairing. Run it on the
machine you want to SSH into (macOS or Linux). It:

1. Determines that machine's **SSH host-key fingerprint** in OpenSSH
   `SHA256:...` form.
2. Mints a **one-time pairing token** and a short **expiry**.
3. Builds a `glassssh://pair?...` URL and renders it as a **QR code** in your
   terminal (and optionally as a PNG).
4. **Advertises** a `_glasspair._tcp` Bonjour/mDNS service on the LAN so the
   iPad app can discover it.

The iPad app scans the QR (or browses Bonjour), pins the host key
(trust-on-first-use), and imports a ready-to-use connection profile.

## Install

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Dependencies: [`zeroconf`](https://pypi.org/project/zeroconf/) (Bonjour/mDNS)
and [`segno`](https://pypi.org/project/segno/) (pure-Python QR codes).

## Usage

```bash
# Advertise for 120s and print the QR (best-guess LAN IP, port 22, hostname).
python glasspair.py

# Pre-fill a username and write a PNG, shorter TTL.
python glasspair.py --user deploy --ttl 60 --png pairing.png

# Print the URL + QR and exit immediately (no Bonjour advertising).
python glasspair.py --dry-run
```

### Options

| Flag        | Default              | Description                                            |
|-------------|----------------------|--------------------------------------------------------|
| `--host`    | best-guess LAN IP    | IP/host the iPad should connect to.                    |
| `--port`    | `22`                 | SSH port to advertise.                                 |
| `--user`    | _(none)_             | Optional username to pre-fill in the profile.          |
| `--service` | this host's hostname | Bonjour service instance name.                         |
| `--ttl`     | `120`                | Seconds the QR/advertisement stays valid.              |
| `--png`     | _(none)_             | Also write the QR as a PNG to this path.               |
| `--dry-run` | off                  | Print URL + QR and exit without advertising.           |

Run `python glasspair.py --help` for the canonical list.

## Pairing flow

```
  desktop/server (glasspair.py)                 iPad (GlassSSH app)
  -----------------------------                 -------------------
  read host key  -> SHA256:...
  mint token + expiry
  build glassssh://pair?... URL
  render QR  ----------------------- scan ----> decode PairingPayload
  advertise _glasspair._tcp -------- browse --> discover service + TXT
                                                pin SHA256 fingerprint (TOFU)
                                                import connection profile
                                                connect; present token on
                                                first connect for verification
```

The QR URL field layout mirrors `Core/Sources/GlassSSHCore/PairingPayload.swift`
(`PairingCodec`) exactly:

```
glassssh://pair?host=<h>&port=<p>&service=<name>&fp=<SHA256:...>&token=<tok>&exp=<unix-seconds>[&user=<u>]
```

The Bonjour TXT record also carries `fp`, `token`, `exp`, and `v` (version) so a
browsing client can cross-check the live advertisement against the scanned QR.

### Security notes

- The fingerprint lets the iPad **pin** the host key on first connect, defeating
  man-in-the-middle attacks during pairing.
- The token is **one-time** and **short-lived** (`--ttl`); generate a fresh QR
  per pairing. The token never grants access by itself — it is a pairing nonce
  the server can verify, not a credential.

## Running the tests

```bash
pip install pytest
python -m pytest tests -q
```

The tests cover the pure functions only (`build_pairing_url`, fingerprint
formatting, token generation); they need no network access or dependencies
beyond `pytest`.
