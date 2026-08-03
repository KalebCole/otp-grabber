#!/bin/bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail() {
  printf 'repository check failed: %s\n' "$1" >&2
  exit 1
}

tracked_noise="$(git ls-files | grep -E '(^|/)(__pycache__|\.build|node_modules|artifacts)(/|$)|\.(pyc|pyo|db|sqlite|sqlite3|pem|key)$' || true)"
[[ -z "$tracked_noise" ]] || fail "generated or sensitive-looking files are tracked:\n$tracked_noise"

personal_values="$(git grep -nEI '/Users/[A-Za-z0-9._-]+|tail[0-9a-f]{6,}|[A-Za-z0-9._%+-]+@(gmail|outlook|icloud)\.com' -- . \
  ':!.github/skills/impeccable/**' ':!scripts/check-repository.sh' || true)"
[[ -z "$personal_values" ]] || fail "machine-specific values found:\n$personal_values"

inline_web_code="$(git grep -nEI '<script[^>]*>[^<]|\son(click|load|error)=' -- 'docs/*.html' || true)"
[[ -z "$inline_web_code" ]] || fail "inline executable web code found:\n$inline_web_code"

for required in README.md SECURITY.md LICENSE docs/index.html .github/workflows/verify.yml; do
  [[ -f "$required" ]] || fail "missing $required"
done

printf 'repository hygiene checks passed\n'
