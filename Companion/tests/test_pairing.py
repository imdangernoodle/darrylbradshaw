"""Unit tests for the pure helpers in ``glasspair``.

These tests deliberately avoid any network/Bonjour/filesystem side effects so
they run fast and offline. The QR-rendering / advertising paths are covered by
the smoke test in the README, not here.
"""

from __future__ import annotations

import base64
import hashlib
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import pytest

# Make ``glasspair`` importable when tests run from the repo root.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import glasspair  # noqa: E402


# --- build_pairing_url -----------------------------------------------------


def test_build_pairing_url_required_fields():
    url = glasspair.build_pairing_url(
        host="10.0.0.5",
        service_name="studio-mac",
        host_fingerprint="SHA256:zzz",
        token="one-time-token",
        port=22,
    )
    parts = urlsplit(url)
    assert parts.scheme == "glassssh"
    assert parts.netloc == "pair"

    q = parse_qs(parts.query)
    assert q["host"] == ["10.0.0.5"]
    assert q["port"] == ["22"]
    assert q["service"] == ["studio-mac"]
    assert q["fp"] == ["SHA256:zzz"]
    assert q["token"] == ["one-time-token"]
    # Optional fields absent.
    assert "user" not in q
    assert "exp" not in q


def test_build_pairing_url_optional_fields():
    url = glasspair.build_pairing_url(
        host="h",
        service_name="s",
        host_fingerprint="SHA256:x",
        token="t",
        port=2200,
        username="deploy",
        expires_at=1_900_000_000,
    )
    q = parse_qs(urlsplit(url).query)
    assert q["user"] == ["deploy"]
    assert q["exp"] == ["1900000000"]
    assert q["port"] == ["2200"]


def test_build_pairing_url_field_order_matches_swift():
    """Order must mirror PairingCodec.makeURL: host, port, service, fp, token, user, exp."""
    url = glasspair.build_pairing_url(
        host="h",
        service_name="s",
        host_fingerprint="SHA256:x",
        token="t",
        username="u",
        expires_at=42,
    )
    query = urlsplit(url).query
    keys = [pair.split("=")[0] for pair in query.split("&")]
    assert keys == ["host", "port", "service", "fp", "token", "user", "exp"]


def test_build_pairing_url_preserves_fingerprint_colon():
    url = glasspair.build_pairing_url(
        host="h", service_name="s", host_fingerprint="SHA256:abc+/def", token="t"
    )
    # The colon after SHA256 must remain unescaped (legal query char), matching
    # Swift's URLComponents. The '+' must be percent-encoded so it is not read
    # as a space.
    assert "fp=SHA256:" in url
    assert "%2B" in url  # '+' encoded


def test_build_pairing_url_rejects_bad_port():
    with pytest.raises(ValueError):
        glasspair.build_pairing_url(
            host="h", service_name="s", host_fingerprint="SHA256:x", token="t", port=0
        )
    with pytest.raises(ValueError):
        glasspair.build_pairing_url(
            host="h",
            service_name="s",
            host_fingerprint="SHA256:x",
            token="t",
            port=70_000,
        )


def test_payload_to_url_round_trips_via_dataclass():
    payload = glasspair.PairingPayload(
        host="10.0.0.5",
        service_name="studio-mac",
        host_fingerprint="SHA256:zzz",
        token="tok",
        port=22,
        username="deploy",
        expires_at=1_900_000_000,
    )
    url = glasspair.payload_to_url(payload)
    q = parse_qs(urlsplit(url).query)
    assert q["host"] == ["10.0.0.5"]
    assert q["user"] == ["deploy"]
    assert q["exp"] == ["1900000000"]


# --- fingerprint formatting ------------------------------------------------


def test_format_fingerprint_known_vector():
    blob = b"hello world"
    expected = "SHA256:" + base64.b64encode(
        hashlib.sha256(blob).digest()
    ).decode().rstrip("=")
    assert glasspair.format_fingerprint(blob) == expected
    # Must not contain base64 padding.
    assert "=" not in glasspair.format_fingerprint(blob)


def test_fingerprint_from_pub_text():
    blob = b"\x00\x00\x00\x0bssh-ed25519fakekeydata"
    b64 = base64.b64encode(blob).decode()
    line = f"ssh-ed25519 {b64} root@host\n"
    assert glasspair.fingerprint_from_pub_text(line) == glasspair.format_fingerprint(
        blob
    )


def test_fingerprint_from_pub_text_rejects_malformed():
    with pytest.raises(ValueError):
        glasspair.fingerprint_from_pub_text("only-one-field")


def test_fingerprint_from_pub_text_rejects_bad_base64():
    with pytest.raises(ValueError):
        glasspair.fingerprint_from_pub_text("ssh-ed25519 not!valid!base64! comment")


def test_parse_ssh_keygen_fingerprint():
    out = "256 SHA256:abc123DEF root@host (ED25519)\n"
    assert glasspair.parse_ssh_keygen_fingerprint(out) == "SHA256:abc123DEF"


def test_parse_ssh_keygen_fingerprint_missing():
    with pytest.raises(ValueError):
        glasspair.parse_ssh_keygen_fingerprint("256 MD5:aa:bb root@host (RSA)")


# --- token -----------------------------------------------------------------


def test_make_token_is_unique_and_urlsafe():
    a = glasspair.make_token()
    b = glasspair.make_token()
    assert a != b
    # token_urlsafe yields only URL-safe chars.
    assert all(c.isalnum() or c in "-_" for c in a)
