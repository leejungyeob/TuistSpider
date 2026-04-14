#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DERIVED_DATA_PATH="${TUIST_SPIDER_RELEASE_DERIVED_DATA_PATH:-/tmp/TuistSpiderReleaseDerived}"
OUTPUT_DIR="${TUIST_SPIDER_RELEASE_OUTPUT_DIR:-$ROOT_DIR/dist}"
ZIP_NAME="${TUIST_SPIDER_RELEASE_ZIP_NAME:-TuistSpider.app.zip}"
OPEN_OUTPUT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --open)
      OPEN_OUTPUT=1
      shift
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --zip-name)
      ZIP_NAME="$2"
      shift 2
      ;;
    -*)
      echo "error: unknown option '$1'" >&2
      exit 1
      ;;
    *)
      echo "error: build-release-zip.sh does not accept positional arguments" >&2
      exit 1
      ;;
  esac
done

mkdir -p /tmp/clang-modules /tmp/swift-modules "$OUTPUT_DIR"

env \
  TUIST_XDG_STATE_HOME="${TUIST_XDG_STATE_HOME:-/tmp}" \
  CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-modules}" \
  SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-/tmp/swift-modules}" \
  tuist generate --path "$ROOT_DIR"

xcodebuild \
  -workspace "$ROOT_DIR/TuistSpider.xcworkspace" \
  -scheme TuistSpider \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/TuistSpider.app"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

printf 'Built app at %s\n' "$APP_PATH"
printf 'Created zip at %s\n' "$ZIP_PATH"

if [ "$OPEN_OUTPUT" -eq 1 ] && command -v open >/dev/null 2>&1; then
  open "$OUTPUT_DIR"
fi
