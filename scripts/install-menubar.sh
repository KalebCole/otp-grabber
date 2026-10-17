#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=--release
if [[ "${1:-}" == --development ]]; then
  MODE=--development
  shift
fi
[[ $# -le 1 ]] || { echo "usage: $0 [--development] [app bundle path]" >&2; exit 64; }

APP_SOURCE="${1:-$ROOT/dist/OTP Grabber.app}"
APP_DEST="$HOME/Applications/OTP Grabber.app"
APP_EXEC="$APP_DEST/Contents/MacOS/OTPGrabberMenuBar"
PLIST="$HOME/Library/LaunchAgents/com.otpgrabber.menubar.plist"
LABEL="com.otpgrabber.menubar"
UID_VALUE="$(id -u)"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "App bundle not found: $APP_SOURCE" >&2
  echo "Build the app or pass the extracted release app bundle path." >&2
  exit 2
fi

# Never stop or replace the running app until the candidate has passed validation.
"$ROOT/scripts/verify-menubar-signature.sh" "$APP_SOURCE" "$MODE"
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
STAGE="$(mktemp -d "$HOME/Applications/.otp-grabber-stage.XXXXXX")"
BACKUP="$(mktemp -d "$HOME/Applications/.otp-grabber-backup.XXXXXX")"
STAGED_APP="$STAGE/OTP Grabber.app"
STAGED_PLIST="$STAGE/$LABEL.plist"
SWAPPING=0
BOOTED_OUT=0

cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$status" -ne 0 && "$SWAPPING" -eq 1 ]]; then
    echo "Update failed; restoring the previous app." >&2
    launchctl bootout "gui/$UID_VALUE" "$PLIST" 2>/dev/null || true
    rm -rf "$APP_DEST"
    rm -f "$PLIST"
    if [[ -d "$BACKUP/OTP Grabber.app" ]]; then
      mv "$BACKUP/OTP Grabber.app" "$APP_DEST" || status=1
    fi
    if [[ -f "$BACKUP/$LABEL.plist" ]]; then
      mv "$BACKUP/$LABEL.plist" "$PLIST" || status=1
      launchctl bootstrap "gui/$UID_VALUE" "$PLIST" || status=1
    fi
  elif [[ "$status" -ne 0 && "$BOOTED_OUT" -eq 1 && -f "$PLIST" ]]; then
    launchctl bootstrap "gui/$UID_VALUE" "$PLIST" || status=1
  fi
  rm -rf "$STAGE"
  if [[ "$status" -eq 0 || ! -e "$BACKUP/OTP Grabber.app" ]]; then
    rm -rf "$BACKUP"
  else
    echo "Previous app backup remains at $BACKUP" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

/usr/bin/ditto "$APP_SOURCE" "$STAGED_APP"
"$ROOT/scripts/verify-menubar-signature.sh" "$STAGED_APP" "$MODE"
cat > "$STAGED_PLIST" <<PLIST_XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$APP_DEST</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST_XML
chmod 644 "$STAGED_PLIST"
/usr/bin/plutil -lint "$STAGED_PLIST"

launchctl bootout "gui/$UID_VALUE" "$PLIST" 2>/dev/null || true
BOOTED_OUT=1
if pgrep -f -u "$UID_VALUE" "$APP_EXEC" >/dev/null; then
  pkill -f -u "$UID_VALUE" "$APP_EXEC" || true
  for _ in {1..20}; do
    if ! pgrep -f -u "$UID_VALUE" "$APP_EXEC" >/dev/null; then break; fi
    sleep 0.25
  done
  if pgrep -f -u "$UID_VALUE" "$APP_EXEC" >/dev/null; then
    echo "OTP Grabber did not quit; close it before installing the update." >&2
    exit 1
  fi
fi

SWAPPING=1
if [[ -d "$APP_DEST" ]]; then mv "$APP_DEST" "$BACKUP/OTP Grabber.app"; fi
if [[ -f "$PLIST" ]]; then mv "$PLIST" "$BACKUP/$LABEL.plist"; fi
mv "$STAGED_APP" "$APP_DEST"
mv "$STAGED_PLIST" "$PLIST"
launchctl bootstrap "gui/$UID_VALUE" "$PLIST"
echo "Waiting for OTP Grabber to launch. If macOS blocks this personal build, use Open Anyway in Privacy & Security." >&2
for _ in {1..120}; do
  if pgrep -f -u "$UID_VALUE" "$APP_EXEC" >/dev/null; then
    echo "Installed $APP_DEST and registered $LABEL for launch at login."
    exit 0
  fi
  sleep 1
done
echo "Updated OTP Grabber did not launch." >&2
exit 1
