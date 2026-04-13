#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_PATH="${1:-.}"
OUTPUT_PATH="${2:-$PWD/exports/tuist-graph.normalized.json}"
SOURCE_FORMAT="${TUIST_SPIDER_SOURCE_FORMAT:-json}"
TMP_DIR="$(mktemp -d /tmp/tuist-spider.XXXXXX)"
STATE_HOME="${TUIST_XDG_STATE_HOME:-/tmp}"
CLANG_CACHE="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-modules}"
SWIFT_CACHE="${SWIFT_MODULECACHE_PATH:-/tmp/swift-modules}"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

if ! command -v tuist >/dev/null 2>&1; then
  echo "error: 'tuist' command not found" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
mkdir -p "$CLANG_CACHE" "$SWIFT_CACHE"

env \
  TUIST_XDG_STATE_HOME="$STATE_HOME" \
  CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
  SWIFT_MODULECACHE_PATH="$SWIFT_CACHE" \
  tuist graph \
  --format "$SOURCE_FORMAT" \
  --no-open \
  --path "$PROJECT_PATH" \
  --output-path "$TMP_DIR"

python3 "$SCRIPT_DIR/normalize_tuist_graph.py" "$TMP_DIR/graph.json" "$OUTPUT_PATH"

printf 'Normalized graph written to %s\n' "$OUTPUT_PATH"
