#!/usr/bin/env python3
"""GlassSSH pairing companion.

Advertises a ``_glasspair._tcp`` Bonjour/mDNS service on the LAN and prints a
QR code that the GlassSSH iPad app can scan to pair (trust-on-first-use) and
connect with a single tap.

The QR code encodes a ``glassssh://pair?...`` URL whose shape mirrors the app's
codec in ``Core/Sources/GlassSSHCore/PairingPayload.swift`` (``PairingCodec``).

Pure, side-effect-free helpers (URL building, fingerprint formatting) live near
the top so they can be unit-tested without touching the network. The Bonjour
advertise loop and CLI live at the bottom.

Usage::

    python glasspair.py --user deploy --ttl 120
    python glasspair.py --dry-run --png pairing.png

Run ``python glasspair.py --help`` for the full list of options.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import secrets
import socket
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence
from urllib.parse import quote, urlencode

# Scheme + action mirror PairingCodec.scheme / PairingCodec.pairAction.
SCHEME = "glassssh"
PAIR_ACTION = "pair"

# Bonjour/mDNS service type the iPad browses for.
SERVICE_TYPE = "_glasspair._tcp.local."

# Default SSH port (matches ConnectionProfile.defaultPort).
DEFAULT_PORT = 22

# Default time-to-live for a pairing QR, in seconds. Kept short by design.
DEFAULT_TTL = 120

# Candidate host-key public-key files, in preference order (Ed25519 first).
DEFAULT_HOST_KEY_PUBS = (
    "/etc/ssh/ssh_host_ed25519_key.pub",
    "/etc/ssh/ssh_host_rsa_key.pub",
    "/etc/ssh/ssh_host_ecdsa_key.pub",
)


# ---------------------------------------------------------------------------
# Pure helpers (no network / filesystem side effects) — unit-tested.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PairingPayload:
    """The data carried by a pairing QR code.

    Field names intentionally mirror the Swift ``PairingPayload`` so the two
    encoders/decoders stay in lock-step.
    """

    host: str
    service_name: str
    host_fingerprint: str
    token: str
    port: int = DEFAULT_PORT
    username: Optional[str] = None
    expires_at: Optional[int] = None  # unix seconds


def build_pairing_url(
    *,
    host: str,
    service_name: str,
    host_fingerprint: str,
    token: str,
    port: int = DEFAULT_PORT,
    username: Optional[str] = None,
    expires_at: Optional[int] = None,
) -> str:
    """Build the ``glassssh://pair?...`` URL.

    The query-item order matches ``PairingCodec.makeURL`` exactly:
    ``host, port, service, fp, token`` then optional ``user`` then optional
    ``exp``. Keeping the order stable makes the output deterministic and easy to
    diff against the Swift implementation, even though decoding is
    order-independent.

    All values are percent-encoded. Notably the ``SHA256:...`` fingerprint's
    colon is preserved (it is a sub-delimiter that is legal in a query value),
    matching ``URLComponents`` behaviour on the Swift side.

    :raises ValueError: if ``port`` is outside the valid 1..65535 range.
    """
    if not 1 <= port <= 65_535:
        raise ValueError(f"port out of range: {port}")

    items: list[tuple[str, str]] = [
        ("host", host),
        ("port", str(port)),
        ("service", service_name),
        ("fp", host_fingerprint),
        ("token", token),
    ]
    if username is not None:
        items.append(("user", username))
    if expires_at is not None:
        items.append(("exp", str(int(expires_at))))

    # Use a safe set that keeps ':' unescaped to mirror URLComponents, which
    # treats ':' as a legal query character.
    query = urlencode(items, quote_via=lambda s, safe, enc, err: quote(s, safe=":"))
    return f"{SCHEME}://{PAIR_ACTION}?{query}"


def payload_to_url(payload: PairingPayload) -> str:
    """Convenience wrapper: build a URL straight from a :class:`PairingPayload`."""
    return build_pairing_url(
        host=payload.host,
        service_name=payload.service_name,
        host_fingerprint=payload.host_fingerprint,
        token=payload.token,
        port=payload.port,
        username=payload.username,
        expires_at=payload.expires_at,
    )


def format_fingerprint(key_blob: bytes) -> str:
    """Format a raw OpenSSH public-key blob as ``SHA256:<b64-no-padding>``.

    The blob is the *decoded* base64 body from the second field of an OpenSSH
    ``.pub`` file (e.g. the bytes of ``AAAAC3Nza...``). OpenSSH computes the
    fingerprint as the unpadded standard-base64 of ``sha256(blob)``.
    """
    digest = hashlib.sha256(key_blob).digest()
    encoded = base64.b64encode(digest).decode("ascii").rstrip("=")
    return f"SHA256:{encoded}"


def fingerprint_from_pub_text(pub_text: str) -> str:
    """Compute a ``SHA256:`` fingerprint from the text of an OpenSSH ``.pub`` file.

    An OpenSSH public-key line looks like ``<type> <base64-blob> [comment]``;
    only the base64 blob is used.

    :raises ValueError: if the line is malformed or the blob is not valid base64.
    """
    parts = pub_text.strip().split()
    if len(parts) < 2:
        raise ValueError("malformed OpenSSH public key line")
    try:
        # binascii.Error (raised on bad base64) is a subclass of ValueError.
        blob = base64.b64decode(parts[1], validate=True)
    except ValueError as exc:
        raise ValueError(f"invalid base64 in public key: {exc}") from exc
    return format_fingerprint(blob)


def parse_ssh_keygen_fingerprint(ssh_keygen_output: str) -> str:
    """Extract the ``SHA256:...`` token from ``ssh-keygen -l -f`` output.

    The output looks like::

        256 SHA256:abc123... root@host (ED25519)

    :raises ValueError: if no ``SHA256:`` token is present.
    """
    for token in ssh_keygen_output.split():
        if token.startswith("SHA256:"):
            return token
    raise ValueError("no SHA256 fingerprint found in ssh-keygen output")


def make_token(num_bytes: int = 32) -> str:
    """Generate a one-time, URL-safe pairing token."""
    return secrets.token_urlsafe(num_bytes)


# ---------------------------------------------------------------------------
# Impure helpers (filesystem / network / subprocess).
# ---------------------------------------------------------------------------


def discover_host_fingerprint(
    candidates: Optional[Sequence[str]] = None,
) -> str:
    """Determine the SSH host-key fingerprint of this machine.

    Tries each candidate ``.pub`` file in order (defaulting to
    :data:`DEFAULT_HOST_KEY_PUBS`). For each, computes the fingerprint locally;
    if local computation fails it falls back to shelling out to
    ``ssh-keygen -l -f``.

    :raises FileNotFoundError: if none of the candidate public keys exist.
    """
    if candidates is None:
        candidates = DEFAULT_HOST_KEY_PUBS
    last_error: Optional[Exception] = None
    for path_str in candidates:
        path = Path(path_str)
        if not path.is_file():
            continue
        try:
            return fingerprint_from_pub_text(path.read_text(encoding="utf-8"))
        except (ValueError, OSError) as exc:
            last_error = exc
            # Fall back to ssh-keygen for this file before giving up on it.
            try:
                return _fingerprint_via_ssh_keygen(path)
            except (OSError, ValueError, subprocess.SubprocessError) as keygen_exc:
                last_error = keygen_exc
                continue

    if last_error is not None:
        raise FileNotFoundError(
            f"could not read any SSH host key from {list(candidates)}: {last_error}"
        )
    raise FileNotFoundError(
        f"no SSH host public key found among {list(candidates)}"
    )


def _fingerprint_via_ssh_keygen(pub_path: Path) -> str:
    """Run ``ssh-keygen -l -f`` and parse the SHA256 fingerprint."""
    result = subprocess.run(
        ["ssh-keygen", "-l", "-E", "sha256", "-f", str(pub_path)],
        capture_output=True,
        text=True,
        check=True,
    )
    return parse_ssh_keygen_fingerprint(result.stdout)


def best_guess_lan_ip() -> str:
    """Best-effort discovery of this host's primary LAN IPv4 address.

    Opens a UDP socket toward a public address (no packets are sent) to learn
    which local interface the OS would route through. Falls back to
    ``127.0.0.1`` if that fails.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def render_qr_ascii(url: str) -> str:
    """Render ``url`` as an ASCII/Unicode QR code suitable for a terminal.

    Uses ``segno`` (preferred, pure-python). Imported lazily so the pure
    functions and tests do not require the dependency.
    """
    import io

    import segno  # local import keeps the module importable without the dep

    # segno's ``terminal`` writes to a stream and returns None, so capture it
    # into a string buffer rather than printing directly.
    buffer = io.StringIO()
    segno.make(url, error="m").terminal(out=buffer, compact=True)
    return buffer.getvalue().rstrip("\n")


def write_qr_png(url: str, path: str, *, scale: int = 8) -> None:
    """Write ``url`` as a PNG QR code to ``path`` using ``segno``."""
    import segno

    segno.make(url, error="m").save(path, scale=scale, border=4)


# ---------------------------------------------------------------------------
# Bonjour advertising.
# ---------------------------------------------------------------------------


def advertise(
    *,
    service_name: str,
    host: str,
    port: int,
    fingerprint: str,
    token: str,
    expires_at: int,
    ttl: int,
) -> None:
    """Advertise the pairing service over Bonjour for ``ttl`` seconds, then stop.

    TXT records carry the fingerprint, token and expiry so a browsing client can
    verify the QR's payload against the live advertisement.
    """
    from zeroconf import ServiceInfo, Zeroconf

    properties = {
        "fp": fingerprint,
        "token": token,
        "exp": str(expires_at),
        "v": "1",
    }
    info = ServiceInfo(
        type_=SERVICE_TYPE,
        name=f"{service_name}.{SERVICE_TYPE}",
        addresses=[socket.inet_aton(host)] if _is_ipv4(host) else [],
        port=port,
        properties=properties,
        server=f"{service_name}.local.",
    )

    zeroconf = Zeroconf()
    try:
        zeroconf.register_service(info)
        print(
            f"Advertising {service_name} on {SERVICE_TYPE} "
            f"({host}:{port}) for {ttl}s. Scan the QR above to pair.",
            file=sys.stderr,
        )
        _sleep_until_expiry(ttl)
    except KeyboardInterrupt:
        print("\nStopping advertisement (interrupted).", file=sys.stderr)
    finally:
        zeroconf.unregister_service(info)
        zeroconf.close()


def _sleep_until_expiry(ttl: int) -> None:
    """Sleep ``ttl`` seconds, allowing Ctrl-C to break out cleanly."""
    deadline = time.monotonic() + ttl
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        time.sleep(min(1.0, remaining))


def _is_ipv4(value: str) -> bool:
    try:
        socket.inet_aton(value)
        return True
    except OSError:
        return False


# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="glasspair",
        description=(
            "Advertise a GlassSSH pairing service over Bonjour and print a "
            "QR code the iPad app can scan to pair."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--host",
        default=None,
        help="LAN IP/host the iPad should connect to (default: best-guess LAN IP).",
    )
    parser.add_argument(
        "--port", type=int, default=DEFAULT_PORT, help="SSH port to advertise."
    )
    parser.add_argument(
        "--user", default=None, help="Optional username to pre-fill in the profile."
    )
    parser.add_argument(
        "--service",
        default=None,
        help="Bonjour service instance name (default: this machine's hostname).",
    )
    parser.add_argument(
        "--ttl",
        type=int,
        default=DEFAULT_TTL,
        help="Seconds the pairing QR/advertisement stays valid.",
    )
    parser.add_argument(
        "--png",
        default=None,
        metavar="PATH",
        help="Also write the QR code as a PNG to this path.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the URL + QR and exit without advertising over Bonjour.",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)

    if args.ttl <= 0:
        print("error: --ttl must be positive", file=sys.stderr)
        return 2

    host = args.host or best_guess_lan_ip()
    service_name = args.service or socket.gethostname().split(".")[0]

    try:
        fingerprint = discover_host_fingerprint()
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    token = make_token()
    expires_at = int(time.time()) + args.ttl

    payload = PairingPayload(
        host=host,
        service_name=service_name,
        host_fingerprint=fingerprint,
        token=token,
        port=args.port,
        username=args.user,
        expires_at=expires_at,
    )

    try:
        url = payload_to_url(payload)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    print(url)
    try:
        print(render_qr_ascii(url))
    except ImportError:
        print("(install 'segno' to render the QR code in the terminal)", file=sys.stderr)

    if args.png:
        try:
            write_qr_png(url, args.png)
            print(f"Wrote QR PNG to {args.png}", file=sys.stderr)
        except ImportError:
            print("error: 'segno' is required for --png", file=sys.stderr)
            return 1

    if args.dry_run:
        return 0

    try:
        advertise(
            service_name=service_name,
            host=host,
            port=args.port,
            fingerprint=fingerprint,
            token=token,
            expires_at=expires_at,
            ttl=args.ttl,
        )
    except ImportError:
        print(
            "error: 'zeroconf' is required to advertise; use --dry-run to skip.",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
