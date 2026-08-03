#!/bin/bash
set -euo pipefail

APP_SOURCE="${1:-$(cd "$(dirname "$0")/.." && pwd)/dist/OTP Grabber.app}"
APP_DEST="$HOME/Applications/OTP Grabber.app"
PLIST="$HOME/Library/LaunchAgents/com.otpgrabber.menubar.plist"
LABEL="com.otpgrabber.menubar"
UID_VALUE="$(id -u)"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "App bundle not found: $APP_SOURCE" >&2
  echo "Run scripts/build-menubar.sh first, or pass an app bundle path." >&2
  exit 2
fi

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP_DEST"
/usr/bin/ditto "$APP_SOURCE" "$APP_DEST"
cat > "$PLIST" <<PLIST_XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$APP_DEST</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST_XML
chmod 644 "$PLIST"
/usr/bin/plutil -lint "$PLIST"
launchctl bootout "gui/$UID_VALUE" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$UID_VALUE" "$PLIST"
printf 'Installed %s and registered %s for launch at login.\n' "$APP_DEST" "$LABEL"
