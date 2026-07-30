#!/usr/bin/env python3
"""Wait for App Store Connect to finish processing the build we just uploaded.

A successful `altool --upload-app` only means Apple accepted the *bytes*.
Processing runs afterwards and can still reject the build — builds 31 and 32 of
this app were both dropped with ITMS-90683 while the workflow reported success,
because nothing ever asked Apple what it decided.

Exits non-zero when the build ends up INVALID, or never appears at all.

Environment:
    ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY  App Store Connect API creds
    BUILD_NUMBER                                CFBundleVersion just uploaded
    BUNDLE_ID                                   app to look under
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1/"

TIMEOUT_SECONDS = 30 * 60
POLL_SECONDS = 30

# How long a build may take to show up before that counts as a rejection.
#
# This has to clear the time a *healthy* build takes to appear, or the check
# fails good builds: 33 took about six minutes and 34 about eight, and a
# five-minute grace failed 34 roughly eighty seconds before Apple's
# confirmation email arrived.
#
# Waiting is the only available signal. Apple exposes no API for delivery
# rejections — a rejected build simply never appears (31 and 32 both behaved
# that way) and the reason arrives by email. So the cost of being certain is
# spending this long before calling it.
APPEARANCE_GRACE_SECONDS = 15 * 60


def fail(message: str) -> None:
    print(f"::error::{message}")
    sys.exit(1)


def make_token() -> str:
    key = os.environ["ASC_PRIVATE_KEY"]
    return jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "exp": int(time.time()) + 900,
            "aud": "appstoreconnect-v1",
        },
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def api(path: str, token: str) -> dict:
    request = urllib.request.Request(
        API + path, headers={"Authorization": "Bearer " + token}
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        fail(f"App Store Connect API {error.code}: {error.read()[:300].decode()}")
        raise  # unreachable; keeps type checkers happy


def main() -> None:
    build_number = os.environ["BUILD_NUMBER"]
    bundle_id = os.environ["BUNDLE_ID"]
    token = make_token()

    apps = api(f"apps?filter[bundleId]={bundle_id}", token)
    if not apps.get("data"):
        fail(f"No app in App Store Connect with bundle id {bundle_id}")
    app_id = apps["data"][0]["id"]

    print(f"Waiting for build {build_number} to finish processing…")
    deadline = time.time() + TIMEOUT_SECONDS
    started = time.time()

    while time.time() < deadline:
        builds = api(
            f"builds?filter[app]={app_id}"
            f"&filter[version]={build_number}&limit=1",
            token,
        )
        data = builds.get("data") or []

        if not data:
            waited = time.time() - started
            if waited > APPEARANCE_GRACE_SECONDS:
                fail(
                    f"Build {build_number} never appeared in App Store Connect "
                    f"after {int(waited)}s. Apple usually emails the reason — "
                    "check for an 'Action needed' message."
                )
            print("  not listed yet…")
            time.sleep(POLL_SECONDS)
            continue

        state = data[0]["attributes"].get("processingState")
        print(f"  processingState={state}")

        if state == "VALID":
            print(f"Build {build_number} is VALID and available in TestFlight.")
            return
        if state in ("INVALID", "FAILED"):
            fail(
                f"App Store Connect rejected build {build_number} "
                f"(processingState={state}). Apple emails the specific ITMS "
                "code; fix it and upload a new build."
            )

        time.sleep(POLL_SECONDS)

    fail(
        f"Build {build_number} was still processing after "
        f"{TIMEOUT_SECONDS // 60} minutes. Not failing the upload itself, but "
        "verify it in App Store Connect before relying on this build."
    )


if __name__ == "__main__":
    main()
