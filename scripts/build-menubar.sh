#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/menubar"
DIST="${DIST_DIR:-$ROOT/dist}"
APP_NAME="OTP Grabber.app"
APP="$DIST/$APP_NAME"
ARCH="${ARCH:-$(uname -m)}"
VERSION="${VERSION:-0.1.0}"
SIGNING_MODE="${SIGNING_MODE:-development}"

case "$SIGNING_MODE" in
  development|release) ;;
  *) echo "Unsupported signing mode: $SIGNING_MODE" >&2; exit 2 ;;
esac

if [[ "$SIGNING_MODE" == release ]]; then
  FINGERPRINT_FILE="$ROOT/signing/identity.sha1"
  [[ -f "$FINGERPRINT_FILE" ]] || {
    echo "Missing $FINGERPRINT_FILE; complete the signing setup before publishing a release" >&2
    exit 1
  }
  SIGNING_IDENTITY="$(tr -d '[:space:]' < "$FINGERPRINT_FILE" | tr '[:lower:]' '[:upper:]')"
  [[ "$SIGNING_IDENTITY" =~ ^[0-9A-F]{40}$ ]] || {
    echo "Invalid certificate fingerprint in $FINGERPRINT_FILE" >&2
    exit 1
  }
  /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGNING_IDENTITY" || {
    echo "Pinned signing identity is unavailable in the keychain" >&2
    exit 1
  }
fi

case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 2 ;;
esac

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$DIST"
swift build --package-path "$PACKAGE" -c release --arch "$ARCH"
BIN_PATH="$(swift build --package-path "$PACKAGE" -c release --arch "$ARCH" --show-bin-path)"
install -m 755 "$BIN_PATH/OTPGrabberMenuBar" "$APP/Contents/MacOS/OTPGrabberMenuBar"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDisplayName</key><string>OTP Grabber</string>
  <key>CFBundleExecutable</key><string>OTPGrabberMenuBar</string>
  <key>CFBundleIdentifier</key><string>com.otpgrabber.menubar</string>
  <key>CFBundleName</key><string>OTP Grabber</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
if [[ "$SIGNING_MODE" == release ]]; then
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" "$APP"
  "$ROOT/scripts/verify-menubar-signature.sh" "$APP" --release
else
  /usr/bin/codesign --force --sign - "$APP"
  "$ROOT/scripts/verify-menubar-signature.sh" "$APP" --development
fi
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
rm -f "$DIST/otp-grabber-menubar-macos-$ARCH.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/otp-grabber-menubar-macos-$ARCH.zip"
printf 'Built %s and %s\n' "$APP" "$DIST/otp-grabber-menubar-macos-$ARCH.zip"
