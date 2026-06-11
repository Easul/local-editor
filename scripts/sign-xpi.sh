#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_DIR="$ROOT/firefox-extension"
SIGNED_DIR="$ROOT/dist/signed"

if [[ -z "${AMO_JWT_ISSUER:-}" || -z "${AMO_JWT_SECRET:-}" ]]; then
  cat >&2 <<'EOF'
Error: AMO_JWT_ISSUER and AMO_JWT_SECRET are required.

Create API credentials at https://addons.mozilla.org/developers/addon/api/key/
Then run:

  export AMO_JWT_ISSUER="your-api-key"
  export AMO_JWT_SECRET="your-api-secret"
  bash scripts/sign-xpi.sh
EOF
  exit 1
fi

mkdir -p "$SIGNED_DIR"

npx --yes web-ext sign \
  --source-dir "$EXT_DIR" \
  --artifacts-dir "$SIGNED_DIR" \
  --channel unlisted \
  --api-key "$AMO_JWT_ISSUER" \
  --api-secret "$AMO_JWT_SECRET"
