#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${OMARCHY_WEATHER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-weather}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVER_SCRIPT="$SCRIPT_DIR/serve-omarchy-weather.py"

if [[ ! -f "$APP_DIR/index.html" ]]; then
  printf 'Omarchy Weather is not installed in %s.\n' "$APP_DIR" >&2
  printf 'Run scripts/install-omarchy.sh from the project directory first.\n' >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'Omarchy Weather needs Python 3 to serve its local app files.\n' >&2
  exit 1
fi

URL="$(python3 "$SERVER_SCRIPT" "$APP_DIR")"

for browser in chromium chromium-browser google-chrome-stable google-chrome brave-browser brave vivaldi-stable vivaldi; do
  if command -v "$browser" >/dev/null 2>&1; then
    exec "$browser" "--app=$URL"
  fi
done

if command -v xdg-open >/dev/null 2>&1; then
  exec xdg-open "$URL"
fi

printf 'No supported browser launcher was found. Open %s in your browser.\n' "$URL" >&2
