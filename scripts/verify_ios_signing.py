#!/usr/bin/env python3
"""
verify_ios_signing.py — fail fast in CI when the signing material is broken.

Designed to run in GitHub Actions BEFORE `flutter build ipa`, so we catch
the "Signing certificate is invalid" failure mode at second 5 instead of
second 300 (after Xcode pod install + archive compile).

How it works
------------
Reads the cert + profile + ASC API key from environment variables (already
present in every iOS workflow on this team's repos), then checks:

  1. The cert in the GH secret unlocks with the password, and its serial
     matches one of Apple's currently-ACTIVE iOS Distribution certs for the
     team. Catches the "GH secret holds a revoked cert" case — exactly the
     failure that bit listo on 2026-05-12.

  2. The provisioning profile in the GH secret references the SAME cert id
     that Apple says is active. Catches the "profile is still bound to a
     deleted cert" case.

  3. The profile is in ACTIVE state on Apple's side (not INVALID, EXPIRED,
     etc.) and is bound to the bundle id we're about to build for. Catches
     "someone regenerated the profile under the wrong name" + "profile got
     orphaned when an old cert was deleted".

Inputs (env vars — all required)
--------------------------------
  IOS_CERTIFICATE         - base64-encoded p12 of the team distribution cert
  IOS_CERTIFICATE_PASSWORD - p12 password
  IOS_PROFILE             - base64-encoded provisioning profile bytes
  ASC_KEY_ID              - App Store Connect API key id (e.g. UL8DX8869P)
  ASC_ISSUER_ID           - App Store Connect issuer id (UUID)
  ASC_PRIVATE_KEY         - ASC .p8 contents (the EC private key)

CLI args
--------
  --bundle-id   The expected bundle identifier (e.g. com.listo.manager).
                If the profile binds a different bundle, we fail.

Exit codes
----------
  0  Everything checks out — build can proceed.
  1  At least one assertion failed — diagnostic written to stderr.
  2  Missing inputs (env vars or required CLI args).

Why this lives next to rotate_team_signing.py
----------------------------------------------
Both consume the same ASC API + team cert. Keep the surface area small;
when the cert rotates, only the rotation script needs to change — this one
just reads whatever Apple says is active right now.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


# ---------------------------------------------------------------------------
# Logging — emit machine-readable lines so the GH Actions step UI shows
# clear per-check status. Each line starts with [PASS] / [FAIL] / [INFO].
# ---------------------------------------------------------------------------

def _log(level: str, message: str) -> None:
    print(f"[{level}] {message}", file=sys.stderr)


def _required_env(name: str) -> str:
    val = os.environ.get(name)
    if not val:
        _log("FAIL", f"required env var {name} is not set")
        sys.exit(2)
    return val


# ---------------------------------------------------------------------------
# ASC API helpers — kept inline (no shared module) so this file can be
# vendored into any iOS repo by `curl`ing it.
# ---------------------------------------------------------------------------

def _asc_token(key_id: str, issuer_id: str, private_key: str) -> str:
    # Lazy import: PyJWT is provided by the workflow via pip in the shared
    # step that already mints ASC tokens for the build-number lookup.
    import jwt

    return jwt.encode(
        {"iss": issuer_id, "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def _asc_get(token: str, url: str):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def _list_active_distribution_certs(token: str) -> dict[str, dict]:
    """Return {asc_cert_id: attributes} for every active iOS Distribution
    cert in the team. Filtering by certificateType client-side because
    Apple's filter param is finicky about multi-value queries."""
    certs: dict[str, dict] = {}
    url = "https://api.appstoreconnect.apple.com/v1/certificates?limit=200"
    while url:
        status, data = _asc_get(token, url)
        if status != 200:
            _log("FAIL", f"ASC list certificates returned HTTP {status}: {data}")
            sys.exit(1)
        for c in data.get("data", []):
            attrs = c["attributes"]
            if attrs.get("certificateType") in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
                certs[c["id"]] = attrs
        url = data.get("links", {}).get("next")
    return certs


def _find_profile_by_uuid(token: str, uuid: str):
    """Find the ASC profile record whose attributes.uuid matches the
    .mobileprovision UUID embedded in the file. Returns the profile record
    (including relationships) or None if not found."""
    url = (
        "https://api.appstoreconnect.apple.com/v1/profiles"
        "?limit=200&include=bundleId,certificates"
    )
    while url:
        status, data = _asc_get(token, url)
        if status != 200:
            _log("FAIL", f"ASC list profiles returned HTTP {status}: {data}")
            sys.exit(1)
        included_by_id = {x["id"]: x for x in data.get("included", [])}
        for p in data.get("data", []):
            if p["attributes"].get("uuid") == uuid:
                # Augment with the resolved bundleId.identifier inline so
                # the caller doesn't need to make a second round trip.
                bid_ref = (
                    p.get("relationships", {}).get("bundleId", {}).get("data", {}) or {}
                ).get("id")
                p["_bundle_identifier"] = (
                    included_by_id.get(bid_ref, {}).get("attributes", {}).get("identifier")
                )
                return p
        url = data.get("links", {}).get("next")
    return None


# ---------------------------------------------------------------------------
# Local cert + profile inspection — pure stdlib + openssl.
# ---------------------------------------------------------------------------

def _p12_serial(p12_bytes: bytes, password: str) -> str:
    """Return the hex serial number of the cert in a .p12. macOS Keychain
    exports use RC2-40-CBC legacy encryption, so OpenSSL 3 needs -legacy."""
    with tempfile.TemporaryDirectory() as td:
        p12_path = Path(td) / "cert.p12"
        p12_path.write_bytes(p12_bytes)
        try:
            certs_pem = subprocess.run(
                [
                    "openssl", "pkcs12", "-in", str(p12_path),
                    "-passin", f"pass:{password}",
                    "-nokeys", "-clcerts", "-legacy",
                ],
                capture_output=True,
                check=True,
            ).stdout
        except subprocess.CalledProcessError as e:
            _log("FAIL", f"failed to unlock .p12 (wrong password?): {e.stderr.decode()[:200]}")
            sys.exit(1)
        serial_out = subprocess.run(
            ["openssl", "x509", "-noout", "-serial"],
            input=certs_pem,
            capture_output=True,
            check=True,
        ).stdout.decode().strip()
        # "serial=ABCDEF..."
        return serial_out.split("=", 1)[1].upper()


def _parse_profile_uuid(profile_bytes: bytes) -> str:
    """The .mobileprovision is a CMS-wrapped plist. The plain plist payload
    is the simplest way to read UUID without spawning `security cms`. We
    extract the plist manually by finding the <?xml … ?> header and the
    matching </plist> tail."""
    head = profile_bytes.find(b"<?xml")
    tail = profile_bytes.rfind(b"</plist>")
    if head < 0 or tail < 0:
        _log("FAIL", "provisioning profile does not contain an XML plist payload")
        sys.exit(1)
    plist = plistlib.loads(profile_bytes[head: tail + len(b"</plist>")])
    uuid = plist.get("UUID")
    if not uuid:
        _log("FAIL", "provisioning profile has no UUID field")
        sys.exit(1)
    return uuid


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument(
        "--bundle-id",
        required=True,
        help="Expected bundle identifier (e.g. com.listo.manager).",
    )
    args = p.parse_args(argv)

    cert_b64 = _required_env("IOS_CERTIFICATE")
    cert_pw = _required_env("IOS_CERTIFICATE_PASSWORD")
    profile_b64 = _required_env("IOS_PROFILE")
    asc_key_id = _required_env("ASC_KEY_ID")
    asc_issuer = _required_env("ASC_ISSUER_ID")
    asc_key = _required_env("ASC_PRIVATE_KEY")

    cert_bytes = base64.b64decode(cert_b64)
    profile_bytes = base64.b64decode(profile_b64)

    _log("INFO", f"verifying signing for bundle {args.bundle_id}")

    # 1) Decode the local cert + extract its serial.
    local_serial = _p12_serial(cert_bytes, cert_pw)
    _log("INFO", f"local .p12 cert serial = {local_serial}")

    # 2) Decode the local profile + extract its UUID (so we can look it up
    #    by exact match in ASC instead of fuzzy-matching by name).
    profile_uuid = _parse_profile_uuid(profile_bytes)
    _log("INFO", f"local profile UUID    = {profile_uuid}")

    # 3) Build an ASC API token and pull current state.
    token = _asc_token(asc_key_id, asc_issuer, asc_key)

    active_certs = _list_active_distribution_certs(token)
    if not active_certs:
        _log("FAIL", "no active iOS Distribution certs in the team — Apple revoked everything?")
        return 1

    # 4) Find the ASC cert whose serial matches our local .p12.
    matching_cert_id = None
    for cid, attrs in active_certs.items():
        # ASC reports serial in hex without dashes; uppercase to match openssl.
        if (attrs.get("serialNumber") or "").upper() == local_serial:
            matching_cert_id = cid
            break

    if matching_cert_id is None:
        _log(
            "FAIL",
            f"the cert in IOS_CERTIFICATE (serial {local_serial}) is NOT in Apple's "
            f"active iOS Distribution list. Apple has revoked it or you uploaded the "
            f"wrong cert. Active serials: "
            f"{[a.get('serialNumber') for a in active_certs.values()]}. "
            f"Rotate via: python3 scripts/rotate_team_signing.py sync",
        )
        return 1
    _log("PASS", f"cert serial {local_serial} is ACTIVE on Apple (cert id {matching_cert_id})")

    # 5) Find the ASC profile by its UUID.
    asc_profile = _find_profile_by_uuid(token, profile_uuid)
    if asc_profile is None:
        _log(
            "FAIL",
            f"profile UUID {profile_uuid} not found on Apple. Either the GH secret "
            f"holds a profile that no longer exists, or it was deleted on the portal. "
            f"Regenerate via: python3 scripts/rotate_team_signing.py sync",
        )
        return 1

    attrs = asc_profile["attributes"]
    state = attrs.get("profileState")
    if state != "ACTIVE":
        _log("FAIL", f"profile {attrs.get('name')!r} state is {state}, not ACTIVE")
        return 1

    # 6) Check it's bound to the bundle we're building for.
    profile_bundle = asc_profile.get("_bundle_identifier")
    if profile_bundle != args.bundle_id:
        _log(
            "FAIL",
            f"profile is bound to bundle {profile_bundle!r} but the build targets "
            f"{args.bundle_id!r}",
        )
        return 1

    # 7) Check the profile references the same cert id we just verified.
    cert_refs = [
        c["id"]
        for c in asc_profile.get("relationships", {}).get("certificates", {}).get("data", []) or []
    ]
    if matching_cert_id not in cert_refs:
        _log(
            "FAIL",
            f"profile references cert ids {cert_refs} but the cert we're going to "
            f"sign with is {matching_cert_id}. The profile needs to be regenerated "
            f"against the active cert: python3 scripts/rotate_team_signing.py sync",
        )
        return 1
    _log(
        "PASS",
        f"profile {attrs.get('name')!r} is ACTIVE, bound to {profile_bundle}, "
        f"references cert {matching_cert_id}",
    )

    _log("PASS", "all signing checks passed — build is safe to proceed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
