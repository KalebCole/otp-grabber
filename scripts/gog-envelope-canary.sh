#!/usr/bin/env bash
# Exercise the real gog JSON search/raw envelopes without modifying Gmail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3.11}"
CONFIG=""
MESSAGE_ID=""
SINCE_MS="$(( $(date +%s) * 1000 - 3600000 ))"
DRY_RUN=0
CONFIRMED=0

usage() {
  echo "usage: $0 --confirm-read-only --config PATH --message-id ID [--since-ms EPOCH_MS] [--dry-run]" >&2
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm-read-only) CONFIRMED=1 ;;
    --config|--message-id|--since-ms)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      case "$1" in
        --config) CONFIG="$2" ;;
        --message-id) MESSAGE_ID="$2" ;;
        --since-ms) SINCE_MS="$2" ;;
      esac
      shift ;;
    --dry-run) DRY_RUN=1 ;;
    *) usage; exit 64 ;;
  esac
  shift
done
[[ "$CONFIRMED" == 1 && -n "$CONFIG" && -n "$MESSAGE_ID" ]] || { usage; exit 64; }
[[ "$SINCE_MS" =~ ^[0-9]+$ ]] || { echo "--since-ms must be an epoch millisecond integer" >&2; exit 64; }
if (( DRY_RUN )); then
  echo "dry-run: would issue gog gmail.messages.search and gmail.raw with --readonly only"
  exit 0
fi

PYTHONPATH="$ROOT" "$PYTHON_BIN" - "$CONFIG" "$MESSAGE_ID" "$SINCE_MS" <<'PY'
import json
import sys
from pathlib import Path

from agent.otp_grabber.config import load_config
from agent.otp_grabber.sources.gmail import GmailSource

config = load_config(Path(sys.argv[1]))
source = GmailSource(
    backend=config.gmail_backend,
    launcher=config.gog_launcher,
    client=config.gog_client,
    account=config.gog_account,
)
result = source.verify_gog_envelopes(message_id=sys.argv[2], since_timestamp_ms=int(sys.argv[3]))
print(json.dumps({"ok": True, "listing_count": result["listing_count"]}, separators=(",", ":")))
PY
