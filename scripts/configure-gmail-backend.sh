#!/usr/bin/env bash
# Atomically change the installed agent's Gmail backend and verify reload readiness.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${HOME}/Library/Application Support/OTP Grabber"
CONFIG="${APP_DIR}/agent.json"
PLIST="${HOME}/Library/LaunchAgents/com.otpgrabber.agent.plist"
LABEL="com.otpgrabber.agent"
PYTHON_BIN="${PYTHON_BIN:-python3.11}"
DRY_RUN=0
BACKEND=""
GOG_LAUNCHER=""
GOG_CLIENT=""
GOG_ACCOUNT=""

usage() {
  cat >&2 <<'USAGE'
usage: configure-gmail-backend.sh [--dry-run] (--gws | --gog --gog-launcher PATH --gog-client NAME --gog-account ADDRESS)

--gog is an explicit opt-in. It stores the supplied non-secret gog runtime
configuration in the private agent configuration, reloads the LaunchAgent,
and verifies authenticated loopback readiness. --gws is the rollback path.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --gws|--rollback-gws) BACKEND="gws" ;;
    --gog) BACKEND="gog" ;;
    --gog-launcher|--gog-client|--gog-account)
      [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 64; }
      case "$1" in
        --gog-launcher) GOG_LAUNCHER="$2" ;;
        --gog-client) GOG_CLIENT="$2" ;;
        --gog-account) GOG_ACCOUNT="$2" ;;
      esac
      shift ;;
    *) usage; exit 64 ;;
  esac
  shift
done

[[ -n "$BACKEND" ]] || { usage; exit 64; }
if [[ "$BACKEND" == "gog" ]]; then
  [[ -n "$GOG_LAUNCHER" ]] || { echo "--gog-launcher is required with --gog" >&2; exit 64; }
  [[ -n "$GOG_CLIENT" ]] || { echo "--gog-client is required with --gog" >&2; exit 64; }
  [[ -n "$GOG_ACCOUNT" ]] || { echo "--gog-account is required with --gog" >&2; exit 64; }
fi

if (( DRY_RUN )); then
  printf 'dry-run: atomically configure Gmail backend %s at %s\n' "$BACKEND" "$CONFIG"
  printf 'dry-run: reload %s and verify authenticated loopback readiness\n' "$LABEL"
  exit 0
fi

"$PYTHON_BIN" -c 'import sys; assert sys.version_info >= (3, 11), "Python 3.11+ is required"'
[[ -f "$CONFIG" ]] || { echo "agent config is missing; run scripts/install-agent.sh first" >&2; exit 66; }
[[ -f "$PLIST" ]] || { echo "LaunchAgent is missing; run scripts/install-agent.sh first" >&2; exit 66; }

BACKUP="$(mktemp "${APP_DIR}/.agent.json.rollback.XXXXXX")"
cp -p "$CONFIG" "$BACKUP"
rollback() {
  mv -f "$BACKUP" "$CONFIG"
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST" || true
}

if [[ "$BACKEND" == "gog" ]]; then
  PYTHONPATH="$ROOT" "$PYTHON_BIN" -c \
    'from pathlib import Path; from agent.otp_grabber.config import update_gmail_backend; import sys; update_gmail_backend(Path(sys.argv[1]), backend="gog", gog_launcher=sys.argv[2], gog_client=sys.argv[3], gog_account=sys.argv[4])' \
    "$CONFIG" "$GOG_LAUNCHER" "$GOG_CLIENT" "$GOG_ACCOUNT"
else
  PYTHONPATH="$ROOT" "$PYTHON_BIN" -c \
    'from pathlib import Path; from agent.otp_grabber.config import update_gmail_backend; import sys; update_gmail_backend(Path(sys.argv[1]), backend="gws")' \
    "$CONFIG"
fi

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST"; then
  echo "LaunchAgent reload failed; restoring previous configuration" >&2
  rollback
  exit 1
fi

TOKEN="$(PYTHONPATH="$ROOT" "$PYTHON_BIN" -c 'from pathlib import Path; from agent.otp_grabber.config import load_config; import sys; print(load_config(Path(sys.argv[1])).token)' "$CONFIG")"
PORT="$(PYTHONPATH="$ROOT" "$PYTHON_BIN" -c 'from pathlib import Path; from agent.otp_grabber.config import load_config; import sys; print(load_config(Path(sys.argv[1])).port)' "$CONFIG")"
for _ in {1..20}; do
  if response="$(curl --config - <<EOF
fail
silent
show-error
max-time = 2
header = "Authorization: Bearer ${TOKEN}"
url = "http://127.0.0.1:${PORT}/v1/health"
EOF
)" \
    && [[ "$response" == '{"ok":true}' ]]; then
    rm -f "$BACKUP"
    printf 'Gmail backend %s enabled; authenticated loopback readiness passed.\n' "$BACKEND"
    exit 0
  fi
  sleep 0.5
done

echo "agent readiness failed; restoring previous configuration" >&2
rollback
exit 1
