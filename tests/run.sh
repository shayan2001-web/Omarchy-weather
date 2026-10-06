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
TEST_HOME="$TEMP_DIR/home"
DATA_HOME="$TEST_HOME/data"
CONFIG_HOME="$TEST_HOME/config"
CACHE_HOME="$TEST_HOME/cache"
RUNTIME_HOME="$TEST_HOME/runtime"

cleanup() {
  if [[ -r "$RUNTIME_HOME/omarchy-weather-server.pid" ]]; then
    read -r server_pid _ < "$RUNTIME_HOME/omarchy-weather-server.pid" || true
    if [[ "${server_pid:-}" =~ ^[0-9]+$ ]]; then
      kill "$server_pid" 2>/dev/null || true
    fi
  fi
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT
mkdir -p "$TEST_HOME"

run_with_test_home() {
  HOME="$TEST_HOME" \
  XDG_DATA_HOME="$DATA_HOME" \
  XDG_CONFIG_HOME="$CONFIG_HOME" \
  XDG_CACHE_HOME="$CACHE_HOME" \
  XDG_RUNTIME_DIR="$RUNTIME_HOME" \
    "$@"
}

WAYBAR_TEST_BIN="$TEMP_DIR/waybar-bin"
WAYBAR_CONFIG="$CONFIG_HOME/waybar/config.jsonc"
mkdir -p "$CONFIG_HOME/waybar" "$WAYBAR_TEST_BIN"
cat > "$WAYBAR_CONFIG" <<'JSONC'
{
  // Keep existing Omarchy config and comments intact.
  "modules-right": [
    "network",
    "clock"
  ],
  "clock": {"format": "%H:%M"},
}
JSONC
STYLE_TARGET="$CONFIG_HOME/waybar/theme-style.css"
printf '#clock { color: white; }\n' > "$STYLE_TARGET"
ln -s "$(basename "$STYLE_TARGET")" "$CONFIG_HOME/waybar/style.css"
cat > "$WAYBAR_TEST_BIN/curl" <<'MOCK'
#!/usr/bin/env sh
exit 0
MOCK
chmod 755 "$WAYBAR_TEST_BIN/curl"

run_configure_waybar() {
  local config_file="${1:-$WAYBAR_CONFIG}"
  run_with_test_home env \
    PATH="$WAYBAR_TEST_BIN:$PATH" \
    WAYBAR_CONFIG_FILE="$config_file" \
    OMARCHY_WEATHER_NO_WAYBAR_RESTART=1 \
      "$ROOT_DIR/scripts/configure-waybar.sh" >/dev/null
}

run_configure_waybar
[[ "$(grep -o '"custom/weather"' "$WAYBAR_CONFIG" | wc -l)" -eq 2 ]]
grep -q 'Keep existing Omarchy config and comments intact.' "$WAYBAR_CONFIG"
python3 - "$WAYBAR_CONFIG" <<'PY'
import json
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
without_comments = re.sub(r"//.*?$", "", source, flags=re.M)
config = json.loads(without_comments)
assert config["modules-right"].count("custom/weather") == 1
assert Path(config["custom/weather"]["exec"]).name == "omarchy-weather-waybar"
assert Path(config["custom/weather"]["on-click"]).name == "omarchy-weather"
PY
grep -q '#custom-weather.stale' "$CONFIG_HOME/waybar/style.css"
grep -q '#clock { color: white; }' "$STYLE_TARGET"
[[ -L "$CONFIG_HOME/waybar/style.css" ]]
CONFIG_BACKUP="$(find "$CONFIG_HOME/waybar" -maxdepth 1 -name 'config.jsonc.backup.*' -print -quit)"
STYLE_BACKUP="$(find "$CONFIG_HOME/waybar" -maxdepth 1 -name 'style.css.backup.*' -print -quit)"
[[ -n "$CONFIG_BACKUP" && -n "$STYLE_BACKUP" ]]
grep -q 'Keep existing Omarchy config and comments intact.' "$CONFIG_BACKUP"
! grep -q 'custom/weather' "$CONFIG_BACKUP"
! grep -q '#custom-weather' "$STYLE_BACKUP"
[[ "$(find "$CONFIG_HOME/waybar" -maxdepth 1 -name 'config.jsonc.backup.*' | wc -l)" -eq 1 ]]
[[ "$(find "$CONFIG_HOME/waybar" -maxdepth 1 -name 'style.css.backup.*' | wc -l)" -eq 1 ]]
run_configure_waybar
[[ "$(grep -o '"custom/weather"' "$WAYBAR_CONFIG" | wc -l)" -eq 2 ]]
[[ "$(find "$CONFIG_HOME/waybar" -maxdepth 1 -name 'config.jsonc.backup.*' | wc -l)" -eq 1 ]]
[[ "$(find "$CONFIG_HOME/waybar" -maxdepth 1 -name 'style.css.backup.*' | wc -l)" -eq 1 ]]

MINIMAL_CONFIG="$CONFIG_HOME/waybar/minimal.jsonc"
printf '{"layer":"top"}\n' > "$MINIMAL_CONFIG"
run_configure_waybar "$MINIMAL_CONFIG"
python3 - "$MINIMAL_CONFIG" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert config["modules-right"] == ["custom/weather"]
assert config["custom/weather"]["return-type"] == "json"
PY

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

if invalid_output="$(run_with_test_home env OMARCHY_WEATHER_PORT=0 python3 \
  "$BIN_DIR/serve-omarchy-weather.py" "$APP_DIR" 2>&1)"; then
  printf 'The local server accepted an invalid port.\n' >&2
  exit 1
fi
[[ "$invalid_output" == *"OMARCHY_WEATHER_PORT must be an integer from 1 to 65535"* ]]

TEST_PORT="$(python3 - <<'PY'
import socket

with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    print(probe.getsockname()[1])
PY
)"
SERVER_URL="$(run_with_test_home env OMARCHY_WEATHER_PORT="$TEST_PORT" python3 \
  "$BIN_DIR/serve-omarchy-weather.py" "$APP_DIR")"
[[ "$SERVER_URL" == "http://127.0.0.1:$TEST_PORT/" ]]
python3 - "$SERVER_URL" <<'PY'
import sys
import urllib.request

with urllib.request.urlopen(sys.argv[1], timeout=2) as response:
    page = response.read().decode("utf-8")
    if response.status != 200 or "<title>Omarchy Weather</title>" not in page:
        raise SystemExit("The local server did not return the installed app")
PY

read -r SERVER_PID _ < "$RUNTIME_HOME/omarchy-weather-server.pid"
REUSED_URL="$(run_with_test_home env OMARCHY_WEATHER_PORT="$TEST_PORT" python3 \
  "$BIN_DIR/serve-omarchy-weather.py" "$APP_DIR")"
read -r REUSED_PID _ < "$RUNTIME_HOME/omarchy-weather-server.pid"
[[ "$REUSED_URL" == "$SERVER_URL" && "$REUSED_PID" == "$SERVER_PID" ]]
mkdir -p "$CACHE_HOME/omarchy-weather"
printf '{}' > "$CACHE_HOME/omarchy-weather/waybar-test.json"

run_with_test_home "$ROOT_DIR/scripts/uninstall-omarchy.sh" >/dev/null
[[ ! -e "$APP_DIR" ]]
[[ ! -e "$BIN_DIR/omarchy-weather" ]]
[[ ! -e "$BIN_DIR/omarchy-weather-waybar" ]]
[[ ! -e "$DATA_HOME/applications/omarchy-weather.desktop" ]]
[[ ! -e "$DATA_HOME/icons/hicolor/192x192/apps/omarchy-weather.png" ]]
[[ ! -e "$DATA_HOME/icons/hicolor/512x512/apps/omarchy-weather.png" ]]
[[ -f "$CONFIG_DIR/config.json" ]]
[[ -f "$CONFIG_DIR/waybar-weather.css" ]]
[[ -f "$WAYBAR_CONFIG" ]]
grep -q '"custom/weather"' "$WAYBAR_CONFIG"
grep -q '#custom-weather.stale' "$STYLE_TARGET"
[[ ! -e "$CACHE_HOME/omarchy-weather" ]]
[[ -d "$CACHE_HOME" ]]
[[ ! -e "$RUNTIME_HOME/omarchy-weather-server.pid" ]]
python3 - "$TEST_PORT" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
deadline = time.monotonic() + 5
while time.monotonic() < deadline:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2):
            time.sleep(0.05)
    except OSError:
        break
else:
    raise SystemExit("The local server was still running after uninstall")
PY

printf 'Passed: syntax, PWA assets/DOM, Waybar fallbacks, and install/upgrade/server/uninstall lifecycle.\n'
