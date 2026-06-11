#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_DIR="$ROOT/firefox-extension"
DIST_DIR="$ROOT/dist"
MANIFEST="$EXT_DIR/manifest.json"

if ! command -v zip >/dev/null 2>&1; then
  echo "Error: zip is required. Install it with: sudo apt install zip" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required." >&2
  exit 1
fi

VERSION="$(python3 - <<'PY' "$MANIFEST"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)["version"])
PY
)"

mkdir -p "$DIST_DIR"

XPI="$DIST_DIR/firefox-local-editor-$VERSION.xpi"
rm -f "$XPI"

(
  cd "$EXT_DIR"
  zip -qr "$XPI" manifest.json background.js content.js style.css
)

echo "$XPI"
