#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/menubar"
DIST="${DIST_DIR:-$ROOT/dist}"
APP_NAME="OTP Grabber.app"
APP="$DIST/$APP_NAME"
ARCH="${ARCH:-$(uname -m)}"
VERSION="${VERSION:-0.1.0}"

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
/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
rm -f "$DIST/otp-grabber-menubar-macos-$ARCH.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/otp-grabber-menubar-macos-$ARCH.zip"
printf 'Built %s and %s\n' "$APP" "$DIST/otp-grabber-menubar-macos-$ARCH.zip"
