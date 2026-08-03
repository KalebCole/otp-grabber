#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=1; shift; fi
[[ $# -eq 0 ]] || { echo "usage: $0 [--dry-run]" >&2; exit 64; }

LABEL="com.otpgrabber.agent"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
if (( DRY_RUN )); then
  printf 'dry-run: stop and remove %s if present\n' "$PLIST"
  exit 0
fi
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
printf 'uninstalled %s (private configuration retained)\n' "$LABEL"
