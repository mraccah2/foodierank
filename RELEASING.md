# Releasing

This document describes the iOS release pipeline that ships FoodieRank to
TestFlight / the App Store. It's the maintainer's reference — a fork can adapt
it to its own Apple account and signing assets.

> **Note:** The included workflow runs on a **self-hosted macOS runner** (it is
> labelled `[self-hosted, macos, ios]`). If you don't have a self-hosted runner,
> change `runs-on` to a GitHub-hosted macOS runner (e.g. `macos-14`) and adjust
> the toolchain setup steps accordingly.

## Workflow

`.github/workflows/deploy-testflight.yml` runs on every push to `main` that
touches app code, and on manual dispatch. It:

1. Installs the signing certificate + provisioning profile from GitHub secrets.
2. Cross-checks the cert/profile against Apple before building
   (`scripts/verify_ios_signing.py`).
3. Builds the Flutter framework, injecting the runtime API key via
   `--dart-define`.
4. Archives with `xcodebuild`, exports an IPA, and uploads to TestFlight.
5. Submits the build for App Store review
   (`scripts/asc_submit_for_review.py`).

## Configuration

App-identity values are read from **repository variables** with fallbacks, and
secrets from **repository secrets**. Set these under
**Settings → Secrets and variables → Actions**.

### Repository variables (Settings → Variables)

| Variable | Example | Purpose |
|----------|---------|---------|
| `IOS_BUNDLE_ID` | `com.example.foodierank` | Your app's bundle identifier. Must match the value in `ios/Runner.xcodeproj`. |
| `APPLE_TEAM_ID` | `ABCDE12345` | Your Apple Developer Team ID. |

If these are unset, the workflow falls back to the original project's values, so
the upstream pipeline keeps working without extra setup. **Forks must set their
own.**

### Repository secrets (Settings → Secrets)

| Secret | Purpose |
|--------|---------|
| `IOS_MAPS_API_KEY` | Google Places API key baked into the release build. |
| `IOS_CERTIFICATE_P12` | Base64-encoded Apple Distribution certificate (`.p12`). |
| `IOS_CERTIFICATE_PASSWORD` | Password for the `.p12`. |
| `IOS_PROVISIONING_PROFILE` | Base64-encoded distribution provisioning profile. |
| `ASC_KEY_ID` | App Store Connect API key ID. |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID. |
| `ASC_PRIVATE_KEY` | App Store Connect API private key (`.p8` contents). |

### Preparing the signing assets

Encode your certificate and provisioning profile for the secrets:

```bash
base64 -i Certificates.p12 | pbcopy          # -> IOS_CERTIFICATE_P12
base64 -i profile.mobileprovision | pbcopy   # -> IOS_PROVISIONING_PROFILE
```

Create the App Store Connect API key under
[Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).

## Versioning

The workflow sets the build number from the GitHub run number and reads the
version name from `pubspec.yaml` (`version: X.Y.Z+build`). Bump the `X.Y.Z`
version in `pubspec.yaml` for a new release.

## Local release build

To build a signed release locally instead of via CI:

```bash
flutter build ipa --release \
  --dart-define-from-file=dart_defines.json \
  --export-options-plist=ExportOptions.plist
```

See the [Flutter iOS deployment docs](https://docs.flutter.dev/deployment/ios)
for details.
