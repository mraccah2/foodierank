#!/usr/bin/env python3
"""Submit the latest VALID build of FoodieRank for App Store review.

Reads ASC credentials from env:
  ASC_KEY_ID
  ASC_ISSUER_ID
  ASC_PRIVATE_KEY     (PEM contents of the .p8)
  ASC_KEY_PATH        (alternative: path to .p8 file)

Optional:
  ASC_WHATS_NEW       (release notes; defaults to a generic line)
  ASC_BUNDLE_ID       (defaults to com.foodierank.foodierank)
  ASC_VERSION         (defaults to pubspec.yaml's version line stripped of build number)
  ASC_RELEASE_TYPE    (AFTER_APPROVAL | MANUAL | SCHEDULED — default AFTER_APPROVAL)
  ASC_BUILD_VERSION   (specific build number to submit; default: latest VALID)
  ASC_MAX_WAIT_SECS   (how long to wait for processing, default 1800 = 30min)
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

try:
    import jwt
except ImportError:
    sys.stderr.write("missing dep: pip install pyjwt cryptography\n")
    sys.exit(2)

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER_ID = os.environ["ASC_ISSUER_ID"]
BUNDLE_ID = os.environ.get("ASC_BUNDLE_ID", "com.foodierank.foodierank")
RELEASE_TYPE = os.environ.get("ASC_RELEASE_TYPE", "AFTER_APPROVAL")
WHATS_NEW = os.environ.get("ASC_WHATS_NEW", "Bug fixes and improvements.")
TARGET_BUILD = os.environ.get("ASC_BUILD_VERSION")  # optional specific build_number
# The marketing version (CFBundleShortVersionString) the target build belongs
# to. Build numbers repeat across trains, so this is what makes the pair unique.
TARGET_TRAIN = os.environ.get("ASC_TRAIN_VERSION")
MAX_WAIT = int(os.environ.get("ASC_MAX_WAIT_SECS", "1800"))


def _key_pem():
    if "ASC_PRIVATE_KEY" in os.environ:
        return os.environ["ASC_PRIVATE_KEY"]
    path = os.environ.get("ASC_KEY_PATH")
    if path and os.path.exists(path):
        with open(path) as f:
            return f.read()
    sys.stderr.write("Set ASC_PRIVATE_KEY or ASC_KEY_PATH\n")
    sys.exit(2)


def make_jwt():
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        _key_pem(),
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def api(method, path, body=None, tolerate=()):
    """Call the ASC API. If the response status is in `tolerate`, return
    {"__error__": code, "__body__": text} instead of raising — lets callers
    handle expected conflicts (e.g. a transient 409 on a just-created resource)
    without aborting the whole submission."""
    url = f"https://api.appstoreconnect.apple.com{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, method=method, data=data)
    req.add_header("Authorization", f"Bearer {make_jwt()}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        if e.code in tolerate:
            return {"__error__": e.code, "__body__": err}
        sys.stderr.write(f"HTTP {e.code} on {method} {path}\n  body={json.dumps(body) if body else '(none)'}\n  err={err}\n")
        raise


def set_whats_new(loc_id, text, attempts=5):
    """Set the release notes, tolerating the transient 409/423 that ASC returns
    when the appStoreVersion localization was only just created. Retries with
    backoff, then soft-skips so it never blocks the actual submission."""
    for attempt in range(1, attempts + 1):
        r = api("PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}", {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": loc_id,
                "attributes": {"whatsNew": text},
            }
        }, tolerate=(409, 423))
        if "__error__" not in r:
            print(f"Set whatsNew on localization {loc_id}")
            return
        print(f"  whatsNew PATCH attempt {attempt}/{attempts} -> HTTP {r['__error__']} "
              f"(version still materializing), retrying…")
        time.sleep(5 * attempt)
    print("  ⚠️  Could not set whatsNew after retries; continuing without updating release notes.")


REVIEW_CONTACT_FIELDS = ("contactFirstName", "contactLastName", "contactEmail", "contactPhone")


def _review_detail(version_id):
    """The version's appStoreReviewDetail resource, or None if it has none."""
    r = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail",
            tolerate=(404,))
    if "__error__" in r:
        return None
    return r.get("data")


def ensure_review_contact(version_id, versions):
    """Make sure the version carries App Review contact details.

    They live on each version's appStoreReviewDetail, and a version created
    through the API starts without them. Apple then refuses the submission with
    a bare 409 on reviewSubmissionItems (ENTITY_ERROR.ATTRIBUTE.REQUIRED on
    contactFirstName/LastName/Email/Phone), which is how 1.3.0 failed on
    2026-08-21 and 2026-10-02 after building and uploading fine both times.

    Copied from the most recent other version that has them, so the contact is
    whoever it was last time and never invented here.
    """
    current = _review_detail(version_id)
    have = (current or {}).get("attributes") or {}
    if all(have.get(f) for f in REVIEW_CONTACT_FIELDS):
        return

    source = None
    for v in versions:
        if v["id"] == version_id:
            continue
        detail = _review_detail(v["id"])
        attrs = (detail or {}).get("attributes") or {}
        if all(attrs.get(f) for f in REVIEW_CONTACT_FIELDS):
            source = (v["attributes"]["versionString"], attrs)
            break
    if source is None:
        sys.exit("No earlier version has App Review contact details to copy. Fill in "
                 "App Review Information (first/last name, email, phone as +<country code> ...) "
                 "on this version in App Store Connect, then re-run.")

    from_version, attrs = source
    fields = {f: attrs[f] for f in REVIEW_CONTACT_FIELDS}
    if current:
        api("PATCH", f"/v1/appStoreReviewDetails/{current['id']}", {
            "data": {"type": "appStoreReviewDetails", "id": current["id"], "attributes": fields},
        })
    else:
        api("POST", "/v1/appStoreReviewDetails", {
            "data": {
                "type": "appStoreReviewDetails",
                "attributes": {**fields, "demoAccountRequired": bool(attrs.get("demoAccountRequired"))},
                "relationships": {
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }
        })
    print(f"Copied App Review contact details from version {from_version}")


def find_app():
    apps = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if not apps["data"]:
        sys.exit(f"App {BUNDLE_ID} not registered in ASC")
    return apps["data"][0]


def wait_for_valid_build(app_id, target_build_number=None, target_train=None):
    """Poll until at least one VALID, non-expired build exists.

    If target_build_number is given, wait specifically for that build.
    Otherwise, accept the latest non-expired VALID build.

    A build number is **not unique**: App Store Connect scopes it per version
    train, so 1.1.0 and 1.1.1 can each hold a build 41 — and on 2026-08-10 they
    did. Matching on the number alone picked the four-day-old 1.1.0 build
    (already VALID) while the real upload was still processing, so the
    submission went to a train that was already released and 409'd on a
    duplicate version string. [target_train] disambiguates; without it this
    falls back to newest-first, which is right but racy.
    """
    started = time.time()
    while True:
        builds = api(
            "GET",
            f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=20"
            "&include=preReleaseVersion",
        )
        trains = {
            item["id"]: item["attributes"]["version"]
            for item in builds.get("included", [])
            if item["type"] == "preReleaseVersions"
        }
        candidates = []
        for b in builds["data"]:
            attr = b["attributes"]
            if attr["expired"]:
                continue
            if target_build_number and attr["version"] != target_build_number:
                continue
            if target_train:
                rel = (b.get("relationships", {})
                       .get("preReleaseVersion", {})
                       .get("data") or {})
                if trains.get(rel.get("id")) != target_train:
                    continue
            candidates.append(b)
        if candidates:
            valid = [b for b in candidates if b["attributes"]["processingState"] == "VALID"]
            if valid:
                return valid[0]
            print(f"  Latest matching build state={candidates[0]['attributes']['processingState']}, waiting…")
        else:
            print("  No matching build yet, waiting…")
        if time.time() - started > MAX_WAIT:
            sys.exit("Timed out waiting for a VALID build")
        time.sleep(30)


def main():
    app = find_app()
    app_id = app["id"]
    print(f"App: {app['attributes']['name']} (id={app_id})")

    print(f"Waiting for VALID build (target={TARGET_BUILD or 'latest'}"
          f"{', train ' + TARGET_TRAIN if TARGET_TRAIN else ''})…")
    build = wait_for_valid_build(app_id, TARGET_BUILD, TARGET_TRAIN)
    build_id = build["id"]
    build_version = build["attributes"]["version"]
    train = build["attributes"]["preReleaseVersion"]["data"]["id"] if False else None  # not used
    print(f"VALID build {build_version} (id={build_id})")

    if build["attributes"].get("usesNonExemptEncryption") is None:
        print(f"Setting usesNonExemptEncryption=false on build {build_version}…")
        api("PATCH", f"/v1/builds/{build_id}", {
            "data": {
                "type": "builds",
                "id": build_id,
                "attributes": {"usesNonExemptEncryption": False},
            }
        })

    pre_rel = api("GET", f"/v1/builds/{build_id}/preReleaseVersion")
    train_version = pre_rel["data"]["attributes"]["version"]
    print(f"Train version (CFBundleShortVersionString): {train_version}")

    versions = api("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")
    editable_states = {
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
        "INVALID_BINARY", "METADATA_REJECTED",
    }
    editable = None
    waiting = None
    for v in versions["data"]:
        attr = v["attributes"]
        if attr["versionString"] != train_version:
            continue
        if attr["appStoreState"] in editable_states:
            editable = v
            break
        if attr["appStoreState"] == "WAITING_FOR_REVIEW":
            waiting = v

    if waiting and not editable:
        attached_build_id = (waiting.get("relationships", {})
                             .get("build", {}).get("data", {}) or {}).get("id")
        if attached_build_id == build_id:
            print(f"Version {train_version} already submitted with this build (state=WAITING_FOR_REVIEW). Nothing to do.")
            return
        print(f"⚠️  Version {train_version} is in WAITING_FOR_REVIEW with a different build attached.")
        print("   This new build will sit in TestFlight; submit it manually after Apple finishes "
              "reviewing the earlier build, or cancel that submission first.")
        return

    if editable:
        version_id = editable["id"]
        print(f"Existing editable version {train_version}: id={version_id} state={editable['attributes']['appStoreState']}")
        api("PATCH", f"/v1/appStoreVersions/{version_id}", {
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "attributes": {"releaseType": RELEASE_TYPE},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }
        })
        print(f"  Attached build {build_version}, releaseType={RELEASE_TYPE}")
    else:
        print(f"Creating new appStoreVersion {train_version}…")
        v = api("POST", "/v1/appStoreVersions", {
            "data": {
                "type": "appStoreVersions",
                "attributes": {
                    "platform": "IOS",
                    "versionString": train_version,
                    "releaseType": RELEASE_TYPE,
                },
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "build": {"data": {"type": "builds", "id": build_id}},
                },
            }
        })
        version_id = v["data"]["id"]
        print(f"  Created version id={version_id}")

    locs = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    if locs["data"]:
        loc_id = locs["data"][0]["id"]
        set_whats_new(loc_id, WHATS_NEW)

    ensure_review_contact(version_id, versions["data"])

    submissions = api("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW")
    if submissions["data"]:
        sub_id = submissions["data"][0]["id"]
        print(f"Reusing reviewSubmission {sub_id}")
    else:
        s = api("POST", "/v1/reviewSubmissions", {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        sub_id = s["data"]["id"]
        print(f"Created reviewSubmission {sub_id}")

    items = api("GET", f"/v1/reviewSubmissions/{sub_id}/items")
    has_item = any(
        (i.get("relationships", {}).get("appStoreVersion", {}).get("data", {}) or {}).get("id") == version_id
        for i in items["data"]
    )
    if not has_item:
        api("POST", "/v1/reviewSubmissionItems", {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }
        })
        print("Linked version to submission")

    api("PATCH", f"/v1/reviewSubmissions/{sub_id}", {
        "data": {
            "type": "reviewSubmissions",
            "id": sub_id,
            "attributes": {"submitted": True},
        }
    })
    final = api("GET", f"/v1/reviewSubmissions/{sub_id}")
    print(f"✅ Submitted. reviewSubmission state={final['data']['attributes']['state']}")


if __name__ == "__main__":
    main()
