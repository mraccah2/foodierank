#!/usr/bin/env bash
#
# Switch the working tree to the guest (unlisted) app identity, in place, for CI.
# CI checks out a throwaway tree, so nothing is restored afterwards; locally,
# use scripts/build_public_ios.sh, which swaps and restores around a build.
#
#   ios/Runner.xcodeproj/project.pbxproj   Runner bundle id -> com.foodierank.foodierank.public
#   ios/Runner/GoogleService-Info.plist    <- ios/config/public/GoogleService-Info.plist
#   ios/Runner/Info.plist                  Google Sign-In URL scheme -> public REVERSED_CLIENT_ID
#
# Prints the guest iOS OAuth client id (for GOOGLE_IOS_CLIENT_ID) on stdout.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PRIVATE_BUNDLE_ID="com.foodierank.foodierank"
PUBLIC_BUNDLE_ID="com.foodierank.foodierank.public"
PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
INFO_PLIST="ios/Runner/Info.plist"
GS_PLIST="ios/Runner/GoogleService-Info.plist"
PUBLIC_GS_PLIST="ios/config/public/GoogleService-Info.plist"

plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

PRIVATE_REVERSED_CLIENT_ID="$(plist_get "$GS_PLIST" REVERSED_CLIENT_ID)"
PUBLIC_REVERSED_CLIENT_ID="$(plist_get "$PUBLIC_GS_PLIST" REVERSED_CLIENT_ID)"
PUBLIC_CLIENT_ID="$(plist_get "$PUBLIC_GS_PLIST" CLIENT_ID)"

sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = ${PRIVATE_BUNDLE_ID};/PRODUCT_BUNDLE_IDENTIFIER = ${PUBLIC_BUNDLE_ID};/" "$PBXPROJ"
sed -i '' -e "s/${PRIVATE_REVERSED_CLIENT_ID}/${PUBLIC_REVERSED_CLIENT_ID}/" \
          -e "s#<string>${PRIVATE_BUNDLE_ID}</string>#<string>${PUBLIC_BUNDLE_ID}</string>#" "$INFO_PLIST"
cp "$PUBLIC_GS_PLIST" "$GS_PLIST"

grep -q "$PUBLIC_REVERSED_CLIENT_ID" "$INFO_PLIST" || { echo "Info.plist URL scheme swap failed" >&2; exit 1; }
[ "$(grep -c "PRODUCT_BUNDLE_IDENTIFIER = ${PUBLIC_BUNDLE_ID};" "$PBXPROJ")" -eq 3 ] || {
  echo "Expected 3 Runner bundle-id entries in $PBXPROJ" >&2; exit 1; }

echo "$PUBLIC_CLIENT_ID"
