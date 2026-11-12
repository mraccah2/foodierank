#!/usr/bin/env python3
"""Fetch (or create) an App Store provisioning profile for a bundle id.

Used by CI for the guest build (com.foodierank.foodierank.public), which has no
profile in GitHub secrets. The profile must be signed for the SAME distribution
certificate CI imported from IOS_CERTIFICATE_P12, so the caller passes that
certificate's serial number and this picks the matching ASC certificate.

Usage:
  asc_app_store_profile.py --bundle-id ID --cert-serial HEX --out PATH

Env: ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY or ASC_KEY_PATH.
Writes the decoded .mobileprovision to PATH.
"""

import argparse
import base64
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_submit_for_review import api  # noqa: E402


def norm_serial(s: str) -> str:
    s = s.strip().upper()
    if s.startswith("SERIAL="):
        s = s[len("SERIAL="):]
    return s.lstrip("0")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--cert-serial", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--name", default=None)
    args = p.parse_args()

    bundles = api("GET", f"/v1/bundleIds?filter[identifier]={args.bundle_id}&limit=50")
    bundle = next(
        (b for b in bundles["data"] if b["attributes"]["identifier"] == args.bundle_id), None
    )
    if not bundle:
        sys.stderr.write(f"No bundle id {args.bundle_id} registered in App Store Connect\n")
        return 1

    want = norm_serial(args.cert_serial)
    certs = api("GET", "/v1/certificates?limit=200")
    cert = next(
        (
            c
            for c in certs["data"]
            if c["attributes"].get("certificateType") in ("DISTRIBUTION", "IOS_DISTRIBUTION")
            and norm_serial(c["attributes"].get("serialNumber", "")) == want
        ),
        None,
    )
    if not cert:
        sys.stderr.write(f"No distribution certificate with serial {want} in App Store Connect\n")
        return 1

    profiles = api("GET", f"/v1/bundleIds/{bundle['id']}/profiles?limit=50")
    content = None
    for prof in profiles["data"]:
        at = prof["attributes"]
        if at.get("profileType") != "IOS_APP_STORE" or at.get("profileState") != "ACTIVE":
            continue
        pcerts = api("GET", f"/v1/profiles/{prof['id']}/certificates?limit=50")
        if any(c["id"] == cert["id"] for c in pcerts["data"]):
            content = at["profileContent"]
            print(f"Using existing profile: {at['name']}")
            break

    if content is None:
        name = args.name or f"{args.bundle_id} App Store"
        created = api(
            "POST",
            "/v1/profiles",
            {
                "data": {
                    "type": "profiles",
                    "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                        "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
                    },
                }
            },
        )
        content = created["data"]["attributes"]["profileContent"]
        print(f"Created profile: {name}")

    with open(args.out, "wb") as f:
        f.write(base64.b64decode(content))
    return 0


if __name__ == "__main__":
    sys.exit(main())
