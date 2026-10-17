#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo "Run this setup on the Mac holding the signing identity." >&2; exit 2; }
[[ $# -eq 2 ]] || { echo "usage: $0 /path/to/identity.p12 CERTIFICATE_SHA1" >&2; exit 64; }
P12="$1"
FINGERPRINT="$(printf '%s' "$2" | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')"
[[ -f "$P12" ]] || { echo "PKCS#12 identity not found: $P12" >&2; exit 2; }
[[ "$FINGERPRINT" =~ ^[0-9A-F]{40}$ ]] || { echo "Expected a 40-character certificate SHA-1 fingerprint." >&2; exit 2; }

for command in gh base64 openssl; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 2; }
done

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
[[ "$repo" == KalebCole/otp-grabber ]] || { echo "Expected KalebCole/otp-grabber, got $repo" >&2; exit 2; }
read -r -s -p "Password used when exporting the .p12: " P12_PASSWORD
printf '\n'
[[ -n "$P12_PASSWORD" ]] || { echo "The .p12 password cannot be empty." >&2; exit 2; }
certificate="$(P12_PASSWORD="$P12_PASSWORD" /usr/bin/openssl pkcs12 -in "$P12" -passin env:P12_PASSWORD -nokeys 2>/dev/null | /usr/bin/openssl x509 -noout -fingerprint -sha1 2>/dev/null)" || {
  echo "The .p12 could not be read with that password." >&2
  exit 1
}
actual_fingerprint="$(printf '%s' "$certificate" | sed 's/^[^=]*=//' | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')"
[[ "$actual_fingerprint" == "$FINGERPRINT" ]] || {
  echo "The .p12 certificate does not match the supplied fingerprint." >&2
  exit 1
}

# A Base64 blob is protected by the GitHub Actions secret store, not by Base64 itself.
/usr/bin/base64 -i "$P12" | tr -d '\n' | gh secret set OTP_SIGNING_P12_BASE64
printf '%s' "$P12_PASSWORD" | gh secret set OTP_SIGNING_P12_PASSWORD
unset P12_PASSWORD

mkdir -p "$ROOT/signing"
printf '%s\n' "$FINGERPRINT" > "$ROOT/signing/identity.sha1"
echo "GitHub signing secrets saved and public fingerprint written to signing/identity.sha1."
echo "Keep an encrypted .p12 backup outside GitHub, then commit and push signing/identity.sha1."
