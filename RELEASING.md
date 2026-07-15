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
   `--dart-define`, and writes `ios/Flutter/Secrets.xcconfig` from
   `IOS_MAPS_API_KEY` so the embedded Maps SDK (map picker) is keyed natively.
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

## Local release build (iOS)

To build a signed release locally instead of via CI:

```bash
flutter build ipa --release \
  --dart-define-from-file=dart_defines.json \
  --export-options-plist=ExportOptions.plist
```

See the [Flutter iOS deployment docs](https://docs.flutter.dev/deployment/ios)
for details.

---

## Android

`.github/workflows/build-android.yml` builds a release **APK** and **AAB** on
every push to `main` (app-code paths) and uploads them as workflow artifacts.

### Configuration

| Name | Type | Purpose |
|------|------|---------|
| `ANDROID_MAPS_API_KEY` | secret | Places API key baked into the Android build (runtime + native manifest). |
| `ANDROID_PACKAGE_NAME` | variable (optional) | Defaults to `com.foodierank.foodierank`. |
| `ANDROID_CERT_SHA1` | variable (optional) | Signing-cert SHA-1 the key is restricted to (public by design). |

### Signing

The build only uses a real upload keystore when **`android/key.properties`**
exists; otherwise it falls back to the **debug** key. A debug-signed
APK/AAB is fine for sideloading and testing but **cannot** be uploaded to the
Play Store.

To produce a Play-uploadable build you need your own **upload keystore**:

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (gitignored):

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Build locally:

```bash
flutter build appbundle --release --dart-define-from-file=dart_defines.json
```

### Publishing to the Play Store (not yet automated)

FoodieRank does not currently have a Play Store CD pipeline. To add one:

1. Register the app on the [Google Play Console](https://play.google.com/console/)
   (one-time $25 developer account).
2. Enable **Play App Signing** and keep your upload keystore safe.
3. Create a **Google Play Developer API** service account, grant it release
   permissions, and download its JSON key.
4. Store the keystore (base64), `key.properties` values, and the service-account
   JSON as GitHub secrets, then extend `build-android.yml` with a signed build
   + an upload step (e.g. `r0adkll/upload-google-play`).
