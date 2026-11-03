#!/usr/bin/env bash
# Seed the CocoaPods CDN cache with every trunk podspec Podfile.lock pins.
#
# CocoaPods always fetches CDN specs over HTTP/2 (cocoapods-core
# cdn_source.rb, `:http_version => :httpv2_0`). From the mini's network the
# CDN keeps failing that with "Error in the HTTP2 framing layer" (first seen
# 2026-11-03 on the Firebase 12.19.3 specs), and `pod install` dies before it
# downloads anything. curl over HTTP/1.1 fetches the same files fine, so put
# them where CocoaPods looks first. Then `pod install` resolves from disk.
#
# Usage: prefetch_pod_specs.sh path/to/Podfile.lock
# Best effort: a file that can't be fetched is left for CocoaPods to try.
set -uo pipefail

lock="${1:?usage: $0 Podfile.lock}"
trunk="${CP_HOME_DIR:-$HOME/.cocoapods}/repos/trunk"
cdn="https://cdn.cocoapods.org"

if [ ! -d "$trunk" ]; then
  echo "No CocoaPods trunk at $trunk; nothing to seed."
  exit 0
fi

fetch() { # url dest
  local tmp="$2.tmp.$$"
  mkdir -p "$(dirname "$2")"
  if curl --http1.1 -fsL --retry 3 --retry-delay 2 "$1" -o "$tmp"; then
    mv "$tmp" "$2"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Top-level "  - Name (version)" / "  - Name/Subspec (version):" lines under
# PODS:, reduced to the root pod name. Development pods (EXTERNAL SOURCES)
# aren't on trunk and just 404, which is fine.
pods=$(awk '/^PODS:/{p=1;next} /^[A-Z]/{p=0} p && /^  - /' "$lock" |
  sed -E 's/^  - "?([^ /"]+)[^ ]* \(([^)]+)\).*/\1 \2/' | sort -u)

seeded=0 failed=0
shards=""
while read -r name version; do
  [ -n "$name" ] || continue
  h=$(printf '%s' "$name" | md5 -q 2>/dev/null || printf '%s' "$name" | md5sum | cut -c1-32)
  a=${h:0:1} b=${h:1:1} c=${h:2:1}
  shards="$shards ${a}_${b}_${c}"
  rel="Specs/$a/$b/$c/$name/$version/$name.podspec.json"
  [ -s "$trunk/$rel" ] && continue
  if fetch "$cdn/$rel" "$trunk/$rel"; then
    seeded=$((seeded + 1))
  else
    failed=$((failed + 1))
  fi
done <<< "$pods"

# Refresh the per-shard version indexes, or a stale index hides the new
# versions and resolution fails with "could not find compatible versions".
for s in $(printf '%s\n' $shards | sort -u); do
  fetch "$cdn/all_pods_versions_$s.txt" "$trunk/all_pods_versions_$s.txt" || true
done

echo "Seeded $seeded podspec(s) over HTTP/1.1; $failed not on trunk or unreachable."
