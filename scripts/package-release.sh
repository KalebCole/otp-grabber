#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${DIST_DIR:-$ROOT/dist/release}"
VERSION="${VERSION:-0.1.0}"

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
