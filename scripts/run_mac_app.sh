#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${TUIST_SPIDER_DERIVED_DATA_PATH:-/tmp/TuistSpiderDerived}"
OPEN_APP=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-open)
      OPEN_APP=0
      shift
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    -*)
      echo "error: unknown option '$1'" >&2
      exit 1
      ;;
    *)
      echo "error: run_mac_app.sh does not accept positional arguments" >&2
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

xcodebuild \
  -workspace "$ROOT_DIR/TuistSpider.xcworkspace" \
  -scheme TuistSpider \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/TuistSpider.app"
printf 'Built app at %s\n' "$APP_PATH"

if [ "$OPEN_APP" -eq 1 ] && command -v open >/dev/null 2>&1; then
  open "$APP_PATH"
fi
