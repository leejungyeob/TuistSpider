#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DERIVED_DATA_PATH="${TUIST_SPIDER_RELEASE_DERIVED_DATA_PATH:-/tmp/TuistSpiderReleaseDerived}"
OUTPUT_DIR="${TUIST_SPIDER_RELEASE_OUTPUT_DIR:-$ROOT_DIR/dist}"
DMG_NAME="${TUIST_SPIDER_RELEASE_DMG_NAME:-TuistSpider.dmg}"
VOLUME_NAME="${TUIST_SPIDER_RELEASE_VOLUME_NAME:-TuistSpider}"
OPEN_OUTPUT=0
SKIP_LAYOUT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --open)
      OPEN_OUTPUT=1
      shift
      ;;
    --skip-layout)
      SKIP_LAYOUT=1
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
    --dmg-name)
      DMG_NAME="$2"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="$2"
      shift 2
      ;;
    -*)
      echo "error: unknown option '$1'" >&2
      exit 1
      ;;
    *)
      echo "error: build-release-dmg.sh does not accept positional arguments" >&2
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
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
BACKGROUND_PATH="$ROOT_DIR/assets/installer/dmg-background.png"
WORK_DIR="$(mktemp -d /tmp/tuistspider-dmg.XXXXXX)"
STAGING_DIR="$WORK_DIR/root"
RW_DMG_PATH="$WORK_DIR/TuistSpider-temp.dmg"
ATTACHED_DEVICE=""

cleanup() {
  if [ -n "$ATTACHED_DEVICE" ]; then
    hdiutil detach "$ATTACHED_DEVICE" -quiet || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [ ! -f "$BACKGROUND_PATH" ]; then
  echo "error: missing DMG background at $BACKGROUND_PATH" >&2
  exit 1
fi

mkdir -p "$STAGING_DIR/.background"
cp -R "$APP_PATH" "$STAGING_DIR/TuistSpider.app"
cp "$BACKGROUND_PATH" "$STAGING_DIR/.background/dmg-background.png"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$RW_DMG_PATH" "$DMG_PATH"
hdiutil create \
  -quiet \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH"

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG_PATH")"
ATTACHED_DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/^\/dev\// && /\/Volumes\// { print $1; exit }')"

if [ -z "$ATTACHED_DEVICE" ]; then
  echo "error: failed to mount writable DMG" >&2
  exit 1
fi

if [ "$SKIP_LAYOUT" -eq 0 ] && command -v osascript >/dev/null 2>&1; then
  osascript <<EOF || echo "warning: Finder layout customization failed; continuing with a basic DMG" >&2
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 1080, 720}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 16
    set background picture of opts to file ".background:dmg-background.png"
    set position of item "TuistSpider.app" of container window to {250, 350}
    set position of item "Applications" of container window to {710, 350}
    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
end tell
EOF
fi

sync
hdiutil detach "$ATTACHED_DEVICE" -quiet
ATTACHED_DEVICE=""

hdiutil convert \
  "$RW_DMG_PATH" \
  -quiet \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH"

printf 'Built app at %s\n' "$APP_PATH"
printf 'Created dmg at %s\n' "$DMG_PATH"

if [ "$OPEN_OUTPUT" -eq 1 ] && command -v open >/dev/null 2>&1; then
  open "$OUTPUT_DIR"
fi
