#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
BUNDLED_GRAPH_PATH="$ROOT_DIR/web/data/current-graph.json"
PORT=4173
PROJECT_PATH=""
EXPORT_ONLY=0
AUTO_OPEN="${TUIST_SPIDER_OPEN:-1}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --port)
      PORT="$2"
      shift 2
      ;;
    --no-open)
      AUTO_OPEN=0
      shift
      ;;
    --export-only)
      EXPORT_ONLY=1
      shift
      ;;
    -*)
      echo "error: unknown option '$1'" >&2
      exit 1
      ;;
    *)
      if [ -n "$PROJECT_PATH" ]; then
        echo "error: project path was already provided: $PROJECT_PATH" >&2
        exit 1
      fi
      PROJECT_PATH="$1"
      shift
      ;;
  esac
done

mkdir -p "$ROOT_DIR/web/data"

if [ -n "$PROJECT_PATH" ]; then
  "$SCRIPT_DIR/export_tuist_graph.sh" "$PROJECT_PATH" "$BUNDLED_GRAPH_PATH"
fi

if [ "$EXPORT_ONLY" -eq 1 ]; then
  printf 'Bundled graph ready at %s\n' "$BUNDLED_GRAPH_PATH"
  exit 0
fi

URL="http://localhost:$PORT"

printf 'Serving TuistSpider at %s\n' "$URL"
printf 'Bundled graph path: %s\n' "$BUNDLED_GRAPH_PATH"

if [ "$AUTO_OPEN" -eq 1 ] && command -v open >/dev/null 2>&1; then
  open "$URL" >/dev/null 2>&1 &
fi

exec python3 -m http.server "$PORT" -d "$ROOT_DIR/web"
