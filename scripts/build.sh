#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/build.sh [host|firefox|chromium|all]

Targets:
  host      Build stripped Native Messaging host binaries.
  firefox   Build Firefox debug XPI, and release XPI when AMO credentials exist.
  chromium  Build Chromium debug ZIP, and release CRX when a Chromium key exists.
  all       Build host, firefox, and chromium. This is the default.

Firefox release credentials:
  AMO_JWT_ISSUER and AMO_JWT_SECRET
  or AMO_KEY_FILE pointing to a text file containing the AMO issuer/secret.

Chromium release credentials:
  CHROMIUM_CRX_KEY points to a private key for --pack-extension.
  CHROMIUM_PACKER_BIN optionally points to Chrome/Edge/Chromium.

Output layout:
  dist/local-editor-host
  dist/host/local-editor-host-<os>-amd64[.exe]
  dist/firefox/local-editor-<version>-firefox-debug.xpi
  dist/firefox/local-editor-<version>-firefox-release.xpi
  dist/chromium/local-editor-<version>-chromium-debug.zip
  dist/chromium/local-editor-<version>-chromium-release.crx
EOF
}

TARGET="${1:-all}"
if [[ "$TARGET" == "-h" || "$TARGET" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$TARGET" != "host" && "$TARGET" != "firefox" && "$TARGET" != "chromium" && "$TARGET" != "all" ]]; then
  echo "Error: target must be host, firefox, chromium, or all." >&2
  usage >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT/dist"
TEMP_DIR="$ROOT/temp"
FIREFOX_DIR="$ROOT/extension/firefox"
CHROMIUM_DIR="$ROOT/extension/chromium"
HOST_DIR="$ROOT/host"
FIREFOX_DIST="$DIST_DIR/firefox"
CHROMIUM_DIST="$DIST_DIR/chromium"
HOST_DIST="$DIST_DIR/host"
EXTENSION_FILES=(manifest.json background.js content.js style.css)

require_command() {
  local command_name="$1"
  local install_hint="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: $command_name is required. $install_hint" >&2
    exit 1
  fi
}

read_version() {
  local manifest_path="$1"
  python3 - "$manifest_path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)["version"])
PY
}

zip_extension() {
  local source_dir="$1"
  local output_file="$2"

  rm -f "$output_file"
  (
    cd "$source_dir"
    zip -qr "$output_file" "${EXTENSION_FILES[@]}"
  )
}

copy_native_manifest() {
  local template="$1"
  local output="$2"

  cp "$template" "$output"
}

parse_amo_key_file() {
  local key_file="$1"

  python3 - "$key_file" <<'PY'
from pathlib import Path
import re
import sys

lines = [
    line.strip().strip("`")
    for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    if line.strip().strip("`") and line.strip() not in {"```", "```text", "```bash"}
]

issuer = None
issuer_index = None
for index, line in enumerate(lines):
    match = re.search(r"user:[^\s`]+:[^\s`]+", line)
    if match:
        issuer = match.group(0)
        issuer_index = index
        break

if not issuer and len(lines) >= 2:
    issuer = lines[0].split(":", 1)[1].strip() if ":" in lines[0] else lines[0]
    issuer_index = 0

secret = None
for index, line in enumerate(lines):
    if issuer_index is not None and index <= issuer_index:
        continue
    value = line.split(":", 1)[1].strip() if ":" in line else line.strip()
    if value:
        secret = value
        break

if not issuer or not secret:
    raise SystemExit("could not parse AMO issuer and secret")

print(issuer)
print(secret)
PY
}

load_amo_credentials() {
  if [[ -n "${AMO_JWT_ISSUER:-}" && -n "${AMO_JWT_SECRET:-}" ]]; then
    return 0
  fi

  if [[ -n "${AMO_KEY_FILE:-}" ]]; then
    if [[ ! -f "$AMO_KEY_FILE" ]]; then
      echo "Error: AMO_KEY_FILE does not exist: $AMO_KEY_FILE" >&2
      exit 1
    fi

    mapfile -t parsed_credentials < <(parse_amo_key_file "$AMO_KEY_FILE")
    if [[ ${#parsed_credentials[@]} -lt 2 ]]; then
      echo "Error: AMO_KEY_FILE must contain AMO issuer and secret." >&2
      exit 1
    fi

    AMO_JWT_ISSUER="${parsed_credentials[0]}"
    AMO_JWT_SECRET="${parsed_credentials[1]}"
    export AMO_JWT_ISSUER AMO_JWT_SECRET
    return 0
  fi

  return 1
}

find_chromium_packer() {
  local candidate
  local candidates=(
    "${CHROMIUM_PACKER_BIN:-}"
    google-chrome
    google-chrome-stable
    chromium
    chromium-browser
    microsoft-edge
    microsoft-edge-stable
    microsoft-edge-beta
    microsoft-edge-dev
  )

  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" ]] && command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done

  return 1
}

build_host() {
  require_command go "Install Go first."

  mkdir -p "$DIST_DIR" "$HOST_DIST"

  (
    cd "$HOST_DIR"
    go build -trimpath -ldflags="-s -w" -o "$DIST_DIR/local-editor-host" .

    for goos in linux darwin windows; do
      local output="$HOST_DIST/local-editor-host-${goos}-amd64"
      if [[ "$goos" == "windows" ]]; then
        output="${output}.exe"
      fi

      CGO_ENABLED=0 GOOS="$goos" GOARCH=amd64 \
        go build -trimpath -ldflags="-s -w" -o "$output" .
    done
  )

  echo "Host: $DIST_DIR/local-editor-host"
  echo "Host packages: $HOST_DIST"
}

build_firefox() {
  require_command python3 "Install python3 first."
  require_command zip "Install zip first."

  local version
  local debug_xpi
  local release_xpi
  local release_source
  local release_tmp
  local signed_xpi

  version="$(read_version "$FIREFOX_DIR/manifest.json")"
  debug_xpi="$FIREFOX_DIST/local-editor-${version}-firefox-debug.xpi"
  release_xpi="$FIREFOX_DIST/local-editor-${version}-firefox-release.xpi"
  release_source="$TEMP_DIR/firefox-release-source"
  release_tmp="$TEMP_DIR/firefox-release-artifacts"

  mkdir -p "$FIREFOX_DIST"
  rm -f "$release_xpi"
  zip_extension "$FIREFOX_DIR" "$debug_xpi"
  copy_native_manifest "$ROOT/native-manifest/local_editor_firefox.json" "$FIREFOX_DIST/local_editor_firefox.json"

  echo "Firefox debug: $debug_xpi"

  if load_amo_credentials; then
    require_command npx "Install nodejs/npm first."
    rm -rf "$release_source" "$release_tmp"
    mkdir -p "$release_source" "$release_tmp"
    cp "$FIREFOX_DIR/"{manifest.json,background.js,content.js,style.css} "$release_source/"

    npx --yes web-ext sign \
      --source-dir "$release_source" \
      --artifacts-dir "$release_tmp" \
      --channel unlisted \
      --api-key "$AMO_JWT_ISSUER" \
      --api-secret "$AMO_JWT_SECRET"

    signed_xpi="$(python3 - "$release_tmp" <<'PY'
from pathlib import Path
import sys

files = sorted(Path(sys.argv[1]).glob("*.xpi"), key=lambda path: path.stat().st_mtime, reverse=True)
if not files:
    raise SystemExit("no signed xpi found")
print(files[0])
PY
)"
    cp "$signed_xpi" "$release_xpi"
    rm -rf "$release_source" "$release_tmp"
    echo "Firefox release: $release_xpi"
  else
    echo "Firefox release: skipped (AMO credentials not provided)"
  fi
}

build_chromium() {
  require_command python3 "Install python3 first."
  require_command zip "Install zip first."

  local version
  local debug_dir
  local debug_zip
  local release_crx
  local generated_crx
  local generated_key
  local packer

  version="$(read_version "$CHROMIUM_DIR/manifest.json")"
  debug_dir="$CHROMIUM_DIST/debug"
  debug_zip="$CHROMIUM_DIST/local-editor-${version}-chromium-debug.zip"
  release_crx="$CHROMIUM_DIST/local-editor-${version}-chromium-release.crx"
  generated_crx="$CHROMIUM_DIST/debug.crx"
  generated_key="$CHROMIUM_DIST/debug.pem"

  rm -rf "$debug_dir"
  mkdir -p "$debug_dir" "$CHROMIUM_DIST"
  rm -f "$release_crx"
  cp "$CHROMIUM_DIR/"{manifest.json,background.js,content.js,style.css} "$debug_dir/"
  zip_extension "$debug_dir" "$debug_zip"
  copy_native_manifest "$ROOT/native-manifest/local_editor_chromium.json" "$CHROMIUM_DIST/local_editor_chromium.json"

  echo "Chromium debug: $debug_zip"
  echo "Chromium unpacked: $debug_dir"

  if [[ -n "${CHROMIUM_CRX_KEY:-}" ]]; then
    if [[ ! -f "$CHROMIUM_CRX_KEY" ]]; then
      echo "Error: CHROMIUM_CRX_KEY does not exist: $CHROMIUM_CRX_KEY" >&2
      exit 1
    fi

    if ! packer="$(find_chromium_packer)"; then
      echo "Error: Chromium release requires Chrome, Edge, or Chromium with --pack-extension." >&2
      exit 1
    fi

    rm -f "$generated_crx" "$generated_key" "$release_crx"
    "$packer" --pack-extension="$debug_dir" --pack-extension-key="$CHROMIUM_CRX_KEY" >/dev/null

    if [[ ! -f "$generated_crx" ]]; then
      echo "Error: expected CRX was not created: $generated_crx" >&2
      exit 1
    fi

    mv "$generated_crx" "$release_crx"
    rm -f "$generated_key"
    echo "Chromium release: $release_crx"
  else
    echo "Chromium release: skipped (CHROMIUM_CRX_KEY not provided)"
  fi
}

case "$TARGET" in
  host)
    build_host
    ;;
  firefox)
    build_firefox
    ;;
  chromium)
    build_chromium
    ;;
  all)
    build_host
    build_firefox
    build_chromium
    ;;
esac
