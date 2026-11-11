#!/usr/bin/env bash
#
# Build the App Store *public/unlisted* iOS variant of FoodieRank.
#
# The default build (bundle com.foodierank.foodierank, distributed privately
# through Apple Business Manager) is untouched: nothing in the repo is changed
# permanently. For the duration of the build this script swaps in the public
# identity, then restores the original files on exit (success, failure or ^C):
#
#   ios/Runner.xcodeproj/project.pbxproj   Runner bundle id -> com.foodierank.foodierank.public
#   ios/Runner/GoogleService-Info.plist    <- ios/config/public/GoogleService-Info.plist
#   ios/Runner/Info.plist                  Google Sign-In URL scheme -> public REVERSED_CLIENT_ID
#   dart defines                           IOS_BUNDLE_ID / GOOGLE_IOS_CLIENT_ID -> public values
#                                          (merged over dart_defines.json into a temp file)
#
# Signing is Xcode automatic signing, authenticated with the App Store Connect
# API key so provisioning profiles for the new bundle id are created on demand.
#
# Usage:
#   ./scripts/build_public_ios.sh [--build-name X.Y.Z] [--build-number N]
#
# Env overrides:
#   ASC_KEY_ID      (default UL8DX8869P)
#   ASC_ISSUER_ID   (default 69a6de7c-c3d8-47e3-e053-5b8c7c11a4d1)
#   ASC_KEY_PATH    (default ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8)
#
# Output: build/ios/public/export/*.ipa  (not uploaded)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

PRIVATE_BUNDLE_ID="com.foodierank.foodierank"
PUBLIC_BUNDLE_ID="com.foodierank.foodierank.public"
TEAM_ID="XTWDQNWHQJ"

ASC_KEY_ID="${ASC_KEY_ID:-UL8DX8869P}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-69a6de7c-c3d8-47e3-e053-5b8c7c11a4d1}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
INFO_PLIST="ios/Runner/Info.plist"
GS_PLIST="ios/Runner/GoogleService-Info.plist"
PUBLIC_GS_PLIST="ios/config/public/GoogleService-Info.plist"
DEFINES_FILE="dart_defines.json"

OUT_DIR="build/ios/public"
ARCHIVE="$OUT_DIR/Runner.xcarchive"
EXPORT_DIR="$OUT_DIR/export"

FLUTTER_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --build-name|--build-number) FLUTTER_ARGS+=("$1" "$2"); shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

for f in "$PBXPROJ" "$INFO_PLIST" "$GS_PLIST" "$PUBLIC_GS_PLIST" "$DEFINES_FILE" "$ASC_KEY_PATH"; do
  [ -f "$f" ] || { echo "Missing required file: $f" >&2; exit 1; }
done

if grep -q "$PUBLIC_BUNDLE_ID" "$PBXPROJ" "$INFO_PLIST" "$GS_PLIST"; then
  echo "The working tree already contains the public identity (an interrupted earlier run?)." >&2
  echo "Restore with: git checkout -- $PBXPROJ $INFO_PLIST $GS_PLIST" >&2
  exit 1
fi

plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

PRIVATE_REVERSED_CLIENT_ID="$(plist_get "$GS_PLIST" REVERSED_CLIENT_ID)"
PUBLIC_REVERSED_CLIENT_ID="$(plist_get "$PUBLIC_GS_PLIST" REVERSED_CLIENT_ID)"
PUBLIC_CLIENT_ID="$(plist_get "$PUBLIC_GS_PLIST" CLIENT_ID)"
[ "$(plist_get "$PUBLIC_GS_PLIST" BUNDLE_ID)" = "$PUBLIC_BUNDLE_ID" ] || {
  echo "$PUBLIC_GS_PLIST is not for $PUBLIC_BUNDLE_ID" >&2; exit 1; }

# --- swap in the public identity, restore on any exit -----------------------
BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/foodierank-public.XXXXXX")"
cp "$PBXPROJ" "$BACKUP_DIR/project.pbxproj"
cp "$INFO_PLIST" "$BACKUP_DIR/Info.plist"
cp "$GS_PLIST" "$BACKUP_DIR/GoogleService-Info.plist"
# Generated.xcconfig is gitignored, but restoring it means a plain Xcode build
# afterwards does not silently pick up the public dart defines.
GENERATED_XCCONFIG="ios/Flutter/Generated.xcconfig"
[ -f "$GENERATED_XCCONFIG" ] && cp "$GENERATED_XCCONFIG" "$BACKUP_DIR/Generated.xcconfig"

restore() {
  cp "$BACKUP_DIR/project.pbxproj" "$PBXPROJ"
  cp "$BACKUP_DIR/Info.plist" "$INFO_PLIST"
  cp "$BACKUP_DIR/GoogleService-Info.plist" "$GS_PLIST"
  [ -f "$BACKUP_DIR/Generated.xcconfig" ] && cp "$BACKUP_DIR/Generated.xcconfig" "$GENERATED_XCCONFIG"
  rm -rf "$BACKUP_DIR"
  echo "Restored the default (private) project files."
}
trap restore EXIT
trap 'exit 130' INT TERM

# Runner target only: the trailing ';' keeps RunnerTests' ids untouched.
sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = ${PRIVATE_BUNDLE_ID};/PRODUCT_BUNDLE_IDENTIFIER = ${PUBLIC_BUNDLE_ID};/" "$PBXPROJ"
sed -i '' -e "s/${PRIVATE_REVERSED_CLIENT_ID}/${PUBLIC_REVERSED_CLIENT_ID}/" \
          -e "s#<string>${PRIVATE_BUNDLE_ID}</string>#<string>${PUBLIC_BUNDLE_ID}</string>#" "$INFO_PLIST"
cp "$PUBLIC_GS_PLIST" "$GS_PLIST"

grep -q "$PUBLIC_REVERSED_CLIENT_ID" "$INFO_PLIST" || { echo "Info.plist URL scheme swap failed" >&2; exit 1; }
[ "$(grep -c "PRODUCT_BUNDLE_IDENTIFIER = ${PUBLIC_BUNDLE_ID};" "$PBXPROJ")" -eq 3 ] || {
  echo "Expected 3 Runner bundle-id entries in $PBXPROJ" >&2; exit 1; }

PUBLIC_DEFINES="$BACKUP_DIR/dart_defines.public.json"
python3 - "$DEFINES_FILE" "$PUBLIC_DEFINES" "$PUBLIC_BUNDLE_ID" "$PUBLIC_CLIENT_ID" <<'PY'
import json, sys
src, dst, bundle_id, client_id = sys.argv[1:]
d = json.load(open(src))
d["IOS_BUNDLE_ID"] = bundle_id
d["GOOGLE_IOS_CLIENT_ID"] = client_id
json.dump(d, open(dst, "w"), indent=2)
PY

# --- build -------------------------------------------------------------------
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Generates ios/Flutter/Generated.xcconfig (dart defines, version) and runs
# pod install; the Dart code itself is compiled by the Xcode build phase.
flutter build ios --release --config-only \
  --dart-define-from-file="$PUBLIC_DEFINES" "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}"

AUTH_ARGS=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  "${AUTH_ARGS[@]}"

EXPORT_PLIST="$BACKUP_DIR/ExportOptions.public.plist"
cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>destination</key>
  <string>export</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_DIR" \
  "${AUTH_ARGS[@]}"

IPA="$(ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1)"
[ -n "$IPA" ] || { echo "exportArchive produced no .ipa" >&2; exit 1; }
echo
echo "Public IPA: $ROOT_DIR/$IPA"
