#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?usage: verify-menubar-signature.sh APP [--release|--development]}"
MODE="${2:---release}"
FINGERPRINT_FILE="$ROOT/signing/identity.sha1"

case "$MODE" in
  --release|--development) ;;
  *) echo "Unknown verification mode: $MODE" >&2; exit 64 ;;
esac

[[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 2; }
PLIST="$APP/Contents/Info.plist"
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
[[ "$identifier" == "com.otpgrabber.menubar" && "$executable" == "OTPGrabberMenuBar" ]] || {
  echo "Unexpected app bundle identifier or executable" >&2
  exit 1
}
[[ -f "$APP/Contents/MacOS/$executable" ]] || { echo "App executable is missing" >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

if [[ "$MODE" == --release ]]; then
  [[ -f "$FINGERPRINT_FILE" ]] || {
    echo "Missing $FINGERPRINT_FILE; complete the signing setup before publishing a release" >&2
    exit 1
  }
  fingerprint="$(tr -d '[:space:]' < "$FINGERPRINT_FILE" | tr '[:lower:]' '[:upper:]')"
  [[ "$fingerprint" =~ ^[0-9A-F]{40}$ ]] || {
    echo "Expected a 40-character certificate SHA-1 fingerprint in $FINGERPRINT_FILE" >&2
    exit 1
  }
  /usr/bin/codesign --verify --verbose=2 \
    -R="certificate leaf = H\"$fingerprint\" and identifier \"com.otpgrabber.menubar\"" \
    "$APP"
  if /usr/bin/codesign --display --verbose=4 "$APP" 2>&1 | /usr/bin/grep -q '^Signature=adhoc$'; then
    echo "Release app is ad hoc signed" >&2
    exit 1
  fi
fi
