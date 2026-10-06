#!/usr/bin/env bash
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
APP_DIR="$DATA_HOME/omarchy-weather"
CACHE_DIR="$CACHE_HOME/omarchy-weather"
BIN_DIR="$HOME/.local/bin"
APPLICATIONS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}/omarchy-weather-${UID}}"
PID_FILE="$RUNTIME_DIR/omarchy-weather-server.pid"

if [[ -r "$PID_FILE" ]] && command -v python3 >/dev/null 2>&1; then
  read -r server_pid _ < "$PID_FILE" || true
  if [[ "${server_pid:-}" =~ ^[0-9]+$ ]]; then
    python3 - "$server_pid" "$APP_DIR" <<'PY'
import os
import signal
import sys
from pathlib import Path

pid = int(sys.argv[1])
app_dir = str(Path(sys.argv[2]).resolve())
try:
    arguments = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    decoded = [argument.decode(errors="replace") for argument in arguments if argument]
    if "http.server" in decoded and "--directory" in decoded:
        directory_index = decoded.index("--directory") + 1
        if directory_index < len(decoded) and str(Path(decoded[directory_index]).resolve()) == app_dir:
            os.kill(pid, signal.SIGTERM)
except (OSError, ValueError, IndexError):
    pass
PY
  fi
  rm -f -- "$PID_FILE"
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    rmdir --ignore-fail-on-non-empty "$RUNTIME_DIR" 2>/dev/null || true
  fi
fi

rm -rf -- "$APP_DIR" "$CACHE_DIR"
rm -f -- \
  "$BIN_DIR/omarchy-weather" \
  "$BIN_DIR/serve-omarchy-weather.py" \
  "$BIN_DIR/omarchy-weather-waybar" \
  "$APPLICATIONS_DIR/omarchy-weather.desktop" \
  "$ICON_DIR/192x192/apps/omarchy-weather.png" \
  "$ICON_DIR/512x512/apps/omarchy-weather.png"

for directory in \
  "$ICON_DIR/192x192/apps" \
  "$ICON_DIR/512x512/apps"; do
  rmdir --ignore-fail-on-non-empty "$directory" 2>/dev/null || true
done

if command -v update-desktop-database >/dev/null 2>&1 && [[ -d "$APPLICATIONS_DIR" ]]; then
  update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi

printf 'Removed the Omarchy Weather desktop launcher, Waybar command, installed app files, and local cache.\n'
printf 'Your location settings and copied snippets in %s were left in place.\n' "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-weather"
printf 'Your active Waybar config/style were not reverted; remove the custom/weather entry manually if desired.\n'
