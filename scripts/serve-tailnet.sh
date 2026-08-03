#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
PORT=8877
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --port) PORT="${2:-}"; shift ;;
    --funnel|--public|--host|--bind)
      echo "public exposure is not supported; use private Tailscale Serve only" >&2
      exit 64
      ;;
    *) echo "usage: $0 [--dry-run] [--port PORT]" >&2; exit 64 ;;
  esac
  shift
done
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "port must be 1-65535" >&2
  exit 64
fi
COMMAND=(tailscale serve --bg --yes "--https=${PORT}" "http://127.0.0.1:${PORT}")
if (( DRY_RUN )); then
  printf 'dry-run:'; printf ' %q' "${COMMAND[@]}"; printf '\n'
  exit 0
fi
"${COMMAND[@]}"
printf 'private tailnet HTTPS proxy enabled for loopback port %s\n' "$PORT"
