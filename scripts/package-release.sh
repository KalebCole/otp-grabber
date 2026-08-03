#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${DIST_DIR:-$ROOT/dist/release}"
[[ $# -le 1 ]] || { echo "usage: $0 [version-or-tag]" >&2; exit 64; }
VERSION="${VERSION:-${1:-0.1.0}}"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]] || {
  echo "invalid release version: $VERSION" >&2
  exit 64
}

rm -rf "$DIST"
mkdir -p "$DIST"

(
  cd "$ROOT/extension"
  /usr/bin/zip -qry "$DIST/otp-grabber-chrome-${VERSION}.zip" .
)

DIST_DIR="$DIST" VERSION="$VERSION" "$ROOT/scripts/build-menubar.sh"

git -C "$ROOT" archive \
  --format=tar.gz \
  --prefix="otp-grabber-${VERSION}/" \
  --output="$DIST/otp-grabber-source-${VERSION}.tar.gz" \
  HEAD

printf 'release artifacts:\n'
find "$DIST" -maxdepth 1 -type f -print | sort
