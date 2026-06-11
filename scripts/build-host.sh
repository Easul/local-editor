#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/dist"

(cd "$ROOT/host" && go build -o "$ROOT/dist/local-editor-host" .)
