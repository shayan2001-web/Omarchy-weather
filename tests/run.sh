#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required test command is missing: %s\n' "$1" >&2
    exit 1
  fi
}

for command_name in bash node python3 jq; do
  require_command "$command_name"
done

for script in scripts/*.sh tests/*.sh; do
  bash -n "$script"
done
node --check app.js
node --check service-worker.js
python3 - <<'PY'
from pathlib import Path

source = Path("scripts/serve-omarchy-weather.py").read_text(encoding="utf-8")
compile(source, "scripts/serve-omarchy-weather.py", "exec")
PY

jq empty manifest.webmanifest config/omarchy-weather.example.json
python3 - "$ROOT_DIR" <<'PY'
import json
import re
import sys
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

root = Path(sys.argv[1])

class IdCollector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []

    def handle_starttag(self, tag, attributes):
        value = dict(attributes).get("id")
        if value:
            self.ids.append(value)

html = (root / "index.html").read_text(encoding="utf-8")
app = (root / "app.js").read_text(encoding="utf-8")
parser = IdCollector()
parser.feed(html)
duplicates = sorted(identifier for identifier, count in Counter(parser.ids).items() if count > 1)
if duplicates:
    raise SystemExit(f"Duplicate HTML ids: {', '.join(duplicates)}")

html_ids = set(parser.ids)
selectors = set(re.findall(r"\$\(\s*['\"]#([^'\"]+)['\"]\s*\)", app))
missing = sorted(selectors - html_ids)
if missing:
    raise SystemExit(f"App.js selectors missing from index.html: {', '.join(missing)}")

manifest = json.loads((root / "manifest.webmanifest").read_text(encoding="utf-8"))
for icon in manifest.get("icons", []):
    path = icon.get("src", "").removeprefix("./")
    if not path or not (root / path).is_file():
        raise SystemExit(f"Manifest icon is missing: {icon.get('src')}")

service_worker = (root / "service-worker.js").read_text(encoding="utf-8")
match = re.search(r"const APP_SHELL = \[(.*?)\];", service_worker, re.S)
if not match:
    raise SystemExit("Could not find the service-worker app shell")
for asset in re.findall(r"['\"]([^'\"]+)['\"]", match.group(1)):
    path = "index.html" if asset in {".", "./"} else asset.removeprefix("./")
    if not (root / path).is_file():
        raise SystemExit(f"Service-worker app-shell asset is missing: {asset}")

settings = json.loads((root / "config/omarchy-weather.example.json").read_text(encoding="utf-8"))
if not (-90 <= settings["latitude"] <= 90 and -180 <= settings["longitude"] <= 180):
    raise SystemExit("Example settings contain invalid coordinates")
if settings.get("unit") not in {"c", "f"}:
    raise SystemExit("Example settings unit must be c or f")
PY

"$ROOT_DIR/tests/waybar-weather.sh"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-weather-tests.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
TEST_HOME="$TEMP_DIR/home"
DATA_HOME="$TEST_HOME/data"
CONFIG_HOME="$TEST_HOME/config"
RUNTIME_HOME="$TEST_HOME/runtime"
mkdir -p "$TEST_HOME"

run_with_test_home() {
  HOME="$TEST_HOME" \
  XDG_DATA_HOME="$DATA_HOME" \
  XDG_CONFIG_HOME="$CONFIG_HOME" \
  XDG_RUNTIME_DIR="$RUNTIME_HOME" \
    "$@"
}

run_with_test_home "$ROOT_DIR/scripts/install-omarchy.sh" >/dev/null
APP_DIR="$DATA_HOME/omarchy-weather"
BIN_DIR="$TEST_HOME/.local/bin"
CONFIG_DIR="$CONFIG_HOME/omarchy-weather"
[[ -x "$BIN_DIR/omarchy-weather" ]]
[[ -x "$BIN_DIR/omarchy-weather-waybar" ]]
[[ -f "$DATA_HOME/applications/omarchy-weather.desktop" ]]
[[ -f "$DATA_HOME/icons/hicolor/192x192/apps/omarchy-weather.png" ]]
[[ -f "$DATA_HOME/icons/hicolor/512x512/apps/omarchy-weather.png" ]]
cmp "$ROOT_DIR/app.js" "$APP_DIR/app.js"
jq -e '.latitude == 33.6844 and .longitude == 73.0479 and .unit == "c"' \
  "$CONFIG_DIR/config.json" >/dev/null

printf '{"latitude": 41.3, "longitude": -72.9, "location": "My saved place", "unit": "f"}\n' \
  > "$CONFIG_DIR/config.json"
printf '/* user stylesheet choice */\n' > "$CONFIG_DIR/waybar-weather.css"
run_with_test_home "$ROOT_DIR/scripts/install-omarchy.sh" >/dev/null
jq -e '.location == "My saved place" and .unit == "f"' \
  "$CONFIG_DIR/config.json" >/dev/null
grep -q 'user stylesheet choice' "$CONFIG_DIR/waybar-weather.css"
cmp "$ROOT_DIR/scripts/waybar-weather.sh" "$BIN_DIR/omarchy-weather-waybar"

run_with_test_home "$ROOT_DIR/scripts/uninstall-omarchy.sh" >/dev/null
[[ ! -e "$APP_DIR" ]]
[[ ! -e "$BIN_DIR/omarchy-weather" ]]
[[ ! -e "$BIN_DIR/omarchy-weather-waybar" ]]
[[ ! -e "$DATA_HOME/applications/omarchy-weather.desktop" ]]
[[ ! -e "$DATA_HOME/icons/hicolor/192x192/apps/omarchy-weather.png" ]]
[[ ! -e "$DATA_HOME/icons/hicolor/512x512/apps/omarchy-weather.png" ]]
[[ -f "$CONFIG_DIR/config.json" ]]
[[ -f "$CONFIG_DIR/waybar-weather.css" ]]

printf 'Passed: syntax, PWA asset/DOM checks, Waybar fallbacks, and install/upgrade/uninstall lifecycle.\n'
