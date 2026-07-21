# FoodieRank

**Find the best restaurants around you.**

FoodieRank is a cross-platform [Flutter](https://flutter.dev) app that surfaces
top-rated restaurants near your current location. It ranks nearby places using
Google's Places API, with filters for cuisine, price level, and open-now, plus a
full-screen photo browser for each spot.

> Ranks restaurants by rating and relevance around your GPS location, with
> cuisine / price / open-now filters and rich photo galleries.

---

## Features

- 📍 **Location-aware** — finds and ranks restaurants around your current position
- ⭐ **Smart ranking** — sorts nearby places by rating and relevance
- 🔎 **Filters** — cuisine type, price level, open-now, and free-text search
- 🖼️ **Photo galleries** — cached, full-screen, zoomable restaurant photos
- 🗺️ **Directions** — hand off to Google Maps for navigation
- 📊 **API usage tracking** — built-in counter to keep an eye on Places API calls
- 📱 **Cross-platform** — iOS, Android, macOS, Linux, Windows, and Web from one codebase

## Screenshots

_Add screenshots or a short demo GIF here._

---

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.0 or newer
  (Dart SDK `>=3.0.0 <4.0.0`)
- A [Google Cloud](https://console.cloud.google.com/) project with the
  **Places API (New)** enabled and an API key
- Platform toolchains for whatever targets you want to build
  (Xcode for iOS/macOS, Android Studio / SDK for Android)

Verify your setup:

```bash
flutter doctor
```

### Quick start

```bash
git clone https://github.com/<your-org>/foodierank.git
cd foodierank
./scripts/setup.sh    # checks Flutter, installs deps, scaffolds local config
```

The setup script installs dependencies and creates the local (gitignored)
config files for you. Then add your Google API keys (step 2 below) and run:

```bash
flutter run --dart-define-from-file=dart_defines.json
```

The manual steps below explain each part in detail.

### 1. Clone and install dependencies

```bash
git clone https://github.com/<your-org>/foodierank.git
cd foodierank
flutter pub get
```

### 2. Get a Google Maps / Places API key

1. In the [Google Cloud console](https://console.cloud.google.com/), create a
   project (or use an existing one).
2. Enable the **Places API (New)**. For the native Android map metadata you may
   also enable **Maps SDK for Android**.
3. Under **APIs & Services → Credentials**, create an API key.
4. **Restrict the key** (strongly recommended for anything you ship):
   - iOS key → restrict to your iOS **bundle identifier**
   - Android key → restrict to your **package name + SHA-1 signing certificate**
   - Restrict each key to only the APIs it needs.

You can use one unrestricted key for local development, or separate restricted
keys per platform.

### 3. Configure the app

No secrets live in source control. Keys are injected at **build time**.

**Dart / app runtime keys** — copy the example and fill in your values:

```bash
cp dart_defines.example.json dart_defines.json   # dart_defines.json is gitignored
```

Then run/build with `--dart-define-from-file`:

```bash
flutter run --dart-define-from-file=dart_defines.json
```

Or pass keys individually:

```bash
flutter run \
  --dart-define=IOS_MAPS_API_KEY=YOUR_IOS_KEY \
  --dart-define=ANDROID_MAPS_API_KEY=YOUR_ANDROID_KEY
```

**Android native manifest key** — the Android build also reads a key for the
`com.google.android.geo.API_KEY` manifest entry. Add it to
`android/local.properties` (gitignored):

```properties
MAPS_API_KEY=YOUR_ANDROID_KEY
```

(See `android/local.properties.example`. Alternatively, set a `MAPS_API_KEY`
environment variable before building.)

**iOS native Maps SDK key** — the embedded map picker uses the Google Maps SDK
for iOS, which reads its key natively (not via `--dart-define`). Copy
`ios/Flutter/Secrets.xcconfig.example` to `ios/Flutter/Secrets.xcconfig`
(gitignored) and set your iOS Maps key:

```
GOOGLE_MAPS_IOS_API_KEY = YOUR_IOS_KEY
```

Enable **Maps SDK for iOS** and **Maps SDK for Android** on the corresponding
keys in the Google Cloud console (in addition to the Places API).

### Configuration reference

| Key | Where | Purpose |
|-----|-------|---------|
| `IOS_MAPS_API_KEY` | `--dart-define` | Places API key used by the iOS app at runtime |
| `ANDROID_MAPS_API_KEY` | `--dart-define` | Places API key used by the Android app at runtime |
| `MAPS_API_KEY` | `android/local.properties` or env | Native Android manifest map key |
| `GOOGLE_MAPS_IOS_API_KEY` | `ios/Flutter/Secrets.xcconfig` | Native iOS Maps SDK key for the map picker |
| `IOS_BUNDLE_ID` | `--dart-define` (optional) | Sent as `X-Ios-Bundle-Identifier` for key restrictions |
| `ANDROID_PACKAGE_NAME` | `--dart-define` (optional) | Sent as `X-Android-Package` for key restrictions |
| `ANDROID_CERT_SHA1` | `--dart-define` (optional) | Sent as `X-Android-Cert` for key restrictions |

The optional identity values only matter if your API keys are restricted by app
identity. For unrestricted development keys you can leave them blank.

### 4. Run

```bash
flutter run --dart-define-from-file=dart_defines.json
```

Grant location permission when prompted, and you'll see restaurants ranked
around you.

### 5. Run the CLI (optional)

`bin/foodierank.dart` runs the same search and ranking pipeline as the app, from
a terminal — useful for comparing rankings across cities, or scripting. It is
plain Dart, so it needs no simulator or device:

```bash
export GOOGLE_MAPS_API_KEY=...      # see note below
dart run bin/foodierank.dart "Times Square, New York" --any-time
dart run bin/foodierank.dart --at 40.7484,-73.9967 --cuisine Italian --json
```

```
  # NAME                          RATING  REVIEWS  PRICE  SCORE  SIGNALS
  1 Mitr Thai Restaurant             4.9     9781  $$      5.12  worth the trip (+1.50)
  2 Osteria La Baia                  4.9     7184  $$$$    4.91  worth the trip (+1.50), touristy (0.61)
```

`--json` and `--csv` emit the full ranking breakdown (quality score, destination
bonus, tourist penalty); `--help` lists every option.

Because there is no build-time `--dart-define` on desktop, the CLI takes its key
from `GOOGLE_MAPS_API_KEY`. It sends no app-attestation headers, so this must be
a key restricted by IP or left unrestricted — **not** either mobile key, which
are locked to the app's bundle id / SHA-1 and will be rejected.

---

## Making it your own (forking)

To ship your own build you'll want your own app identity:

- **Bundle / package id** — replace `com.foodierank.foodierank`:
  - iOS: set `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj`
  - Android: `applicationId` / `namespace` in `android/app/build.gradle` (and
    the package path under `android/app/src/main/kotlin/...`)
- **Display name & icons** — `assets/icon.png` + `flutter_launcher_icons.yaml`
  (run `flutter pub run flutter_launcher_icons`), and the app label in
  `AndroidManifest.xml` / iOS `Info.plist`.
- **API keys** — use your own, restricted to your new app identity.
- **Signing & release** — see [RELEASING.md](RELEASING.md).

---

## Project structure

```
bin/
  foodierank.dart            # Command-line entry point (shares the app's ranking)
lib/
  main.dart                  # App entry point, location bootstrap
  config.dart                # Build-time configuration (keys via --dart-define)
  models/                    # Restaurant + location models
  screens/                   # Splash + restaurant list screens
  services/                  # Places API client, ranking, navigation, usage tracking
  utils/                     # Flutter-free helpers shared with bin/
  widgets/                   # Restaurant cards, photo viewer
assets/                      # Icons, splash, fonts
android/ ios/ macos/ linux/ windows/ web/   # Platform runners
```

## Building for release

```bash
# Android
flutter build appbundle --release --dart-define-from-file=dart_defines.json

# iOS (archive/IPA handled by Xcode or CI — see RELEASING.md)
flutter build ios --release --dart-define-from-file=dart_defines.json
```

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for
setup, style, and pull-request guidelines.

## Security

Secrets are never committed — a [gitleaks](https://github.com/gitleaks/gitleaks)
pre-commit hook and a CI secret-scan guard the repo. See
[CONTRIBUTING.md](CONTRIBUTING.md#secrets) before adding any credential-like
value.

## License

Released under the [MIT License](LICENSE).
