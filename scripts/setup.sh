#!/usr/bin/env bash
#
# FoodieRank one-time developer setup.
#
# Verifies your toolchain, installs dependencies, and scaffolds the local
# (gitignored) config files you need to run the app. Safe to run repeatedly —
# it never overwrites an existing config file.
#
# Usage:
#   ./scripts/setup.sh
#
set -euo pipefail

# Resolve repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# --- pretty output helpers ---------------------------------------------------
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"; RED="$(printf '\033[31m')"; RESET="$(printf '\033[0m')"
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
step()  { printf "\n${BOLD}==>${RESET} %s\n" "$1"; }
ok()    { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }
fail()  { printf "  ${RED}✗${RESET} %s\n" "$1"; }

echo "${BOLD}FoodieRank setup${RESET}"

# --- 1. Check Flutter --------------------------------------------------------
step "Checking Flutter toolchain"
if ! command -v flutter >/dev/null 2>&1; then
  fail "Flutter not found on your PATH."
  echo "     Install it: https://docs.flutter.dev/get-started/install"
  exit 1
fi
ok "flutter found: $(flutter --version 2>/dev/null | head -n1)"
warn "Run 'flutter doctor' separately to validate platform toolchains (Xcode, Android SDK, ...)."

# --- 2. Install dependencies -------------------------------------------------
step "Installing Dart/Flutter dependencies"
flutter pub get
ok "flutter pub get complete"

# --- 3. Scaffold runtime config (dart_defines.json) --------------------------
step "Setting up local configuration"
if [ -f dart_defines.json ]; then
  ok "dart_defines.json already exists — leaving it untouched"
else
  cp dart_defines.example.json dart_defines.json
  ok "Created dart_defines.json from the example template"
  warn "Edit dart_defines.json and add your Google Maps/Places API keys."
fi

# --- 4. Scaffold Android native manifest key ---------------------------------
ANDROID_LOCAL_PROPS="android/local.properties"
if [ -f "$ANDROID_LOCAL_PROPS" ]; then
  if grep -q '^MAPS_API_KEY=' "$ANDROID_LOCAL_PROPS"; then
    ok "android/local.properties already has MAPS_API_KEY"
  else
    printf '\n# Google Maps API key for the native Android manifest\nMAPS_API_KEY=\n' >> "$ANDROID_LOCAL_PROPS"
    warn "Appended an empty MAPS_API_KEY to android/local.properties — fill it in."
  fi
else
  warn "android/local.properties not found yet (Flutter usually generates it on first build)."
  warn "After your first build, add: MAPS_API_KEY=YOUR_ANDROID_KEY"
fi

# --- 5. Optional: install the gitleaks pre-commit hook -----------------------
step "Secret-scanning pre-commit hook (optional)"
if command -v pre-commit >/dev/null 2>&1; then
  pre-commit install >/dev/null 2>&1 && ok "gitleaks pre-commit hook installed" \
    || warn "Could not install pre-commit hook automatically."
else
  warn "'pre-commit' not installed — skipping. Install with 'pip install pre-commit' then run 'pre-commit install'."
fi

# --- Done --------------------------------------------------------------------
step "Next steps"
cat <<EOF
  1. Get a Google Maps/Places API key (Places API New enabled):
       https://console.cloud.google.com/
  2. Add your keys to:
       - ${BOLD}dart_defines.json${RESET}        (runtime keys, iOS + Android)
       - ${BOLD}android/local.properties${RESET}  (MAPS_API_KEY for the native manifest)
  3. Run the app:
       ${BOLD}flutter run --dart-define-from-file=dart_defines.json${RESET}

  See README.md for full details.
EOF
ok "Setup complete."
