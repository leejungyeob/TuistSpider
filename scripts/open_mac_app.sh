#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
OPEN_PROJECT=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-open)
      OPEN_PROJECT=0
      shift
      ;;
    -*)
      echo "error: unknown option '$1'" >&2
      exit 1
      ;;
    *)
      echo "error: open_mac_app.sh does not accept positional arguments" >&2
      exit 1
      ;;
  esac
done

mkdir -p /tmp/clang-modules /tmp/swift-modules

env \
  TUIST_XDG_STATE_HOME="${TUIST_XDG_STATE_HOME:-/tmp}" \
  CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-modules}" \
  SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-/tmp/swift-modules}" \
  tuist generate --path "$ROOT_DIR"

printf 'Generated project at %s\n' "$ROOT_DIR/TuistSpider.xcodeproj"

if [ "$OPEN_PROJECT" -eq 1 ] && command -v open >/dev/null 2>&1; then
  open "$ROOT_DIR/TuistSpider.xcodeproj"
fi
