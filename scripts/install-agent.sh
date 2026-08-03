#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=1; shift; fi
[[ $# -eq 0 ]] || { echo "usage: $0 [--dry-run]" >&2; exit 64; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${HOME}/Library/Application Support/OTP Grabber"
CONFIG="${APP_DIR}/agent.json"
LOG_DIR="${HOME}/Library/Logs/OTP Grabber"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST="${PLIST_DIR}/com.otpgrabber.agent.plist"
if [[ -z "${PYTHON_BIN:-}" ]]; then
  if command -v python3.11 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3.11)"
  else
    PYTHON_BIN="python3"
  fi
fi
LABEL="com.otpgrabber.agent"

if (( DRY_RUN )); then
  printf 'dry-run: generate private config at %s (mode 600)\n' "$CONFIG"
  printf 'dry-run: install %s bound to 127.0.0.1\n' "$PLIST"
  exit 0
fi

"$PYTHON_BIN" -c 'import sys; assert sys.version_info >= (3, 11), "Python 3.11+ is required"'
mkdir -p "$APP_DIR" "$LOG_DIR" "$PLIST_DIR"
chmod 700 "$APP_DIR" "$LOG_DIR"
if [[ ! -f "$CONFIG" ]]; then
  PYTHONPATH="$ROOT" "$PYTHON_BIN" -c "from agent.otp_grabber.config import generate_config; generate_config()"
fi
chmod 600 "$CONFIG"
env ROOT="$ROOT" PYTHON_BIN="$PYTHON_BIN" CONFIG="$CONFIG" LOG_DIR="$LOG_DIR" PLIST="$PLIST" \
  "$PYTHON_BIN" - "$ROOT/scripts/com.otpgrabber.agent.plist.template" <<'PY'
import html
import os
import pathlib
import sys
from string import Template

template = Template(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
values = {key: html.escape(os.environ[key]) for key in ("ROOT", "PYTHON_BIN", "CONFIG", "LOG_DIR")}
pathlib.Path(os.environ["PLIST"]).write_text(template.substitute(values), encoding="utf-8")
PY
chmod 644 "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
printf 'installed private loopback agent: %s\n' "$PLIST"
