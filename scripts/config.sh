# shellcheck shell=bash
# Shared settings for the Pufflet runtime build. Sourced by every script.
set -euo pipefail

ROOT="${PUFFLET_RUNTIME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC="$ROOT/sources"                  # CrossOver import + our commits
WORK="${PUFFLET_RUNTIME_WORK:-$ROOT/build}"
DL="$WORK/downloads"
DEPS="$WORK/deps"                    # x86_64 host libraries (prefix)
TOOLS="$WORK/wine-tools"             # native arm64 winebuild/widl/wrc/...
WBUILD="$WORK/wine-x86_64"
INSTALL="$WORK/install"              # staged runtime: wine/ + Frameworks/
LOGS="$WORK/logs"
JOBS="$(sysctl -n hw.ncpu)"
BREW="${BREW_PREFIX:-/opt/homebrew}"

export MACOSX_DEPLOYMENT_TARGET=14.0
mkdir -p "$DL" "$DEPS" "$LOGS"

# Downloads a pinned file once and verifies it.
fetch() { # url sha256 name
    local out="$DL/$3"
    [ -f "$out" ] || { curl -fSL --retry 3 -o "$out.part" "$1" && mv "$out.part" "$out"; }
    echo "$2  $out" | shasum -a 256 -c - >/dev/null || { echo "checksum mismatch: $3" >&2; rm -f "$out"; return 1; }
}

log() { printf '\n==== %s\n' "$*"; }
