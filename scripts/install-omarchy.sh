#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
APP_DIR="$DATA_HOME/omarchy-weather"
CONFIG_DIR="$CONFIG_HOME/omarchy-weather"
CONFIG_FILE="$CONFIG_DIR/config.json"
BIN_DIR="$HOME/.local/bin"
APPLICATIONS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'Python 3 is required for the local Omarchy launcher.\n' >&2
  printf 'On Arch Linux, install it with: sudo pacman -S python\n' >&2
  exit 1
fi

app_files=(
  index.html
  styles.css
  app.js
  manifest.webmanifest
  service-worker.js
  icon.svg
  icon-192.png
  icon-512.png
)

for file in \
  "${app_files[@]}" \
  scripts/launch-omarchy-weather.sh \
  scripts/serve-omarchy-weather.py \
  scripts/waybar-weather.sh \
  config/omarchy-weather.example.json \
  config/waybar-weather-module.jsonc \
  config/waybar-weather.css; do
  if [[ ! -f "$PROJECT_DIR/$file" ]]; then
    printf 'Required app file is missing: %s\n' "$PROJECT_DIR/$file" >&2
    exit 1
  fi
done

mkdir -p "$APP_DIR" "$CONFIG_DIR" "$BIN_DIR" "$APPLICATIONS_DIR"
for file in "${app_files[@]}"; do
  install -m 644 "$PROJECT_DIR/$file" "$APP_DIR/$file"
done

install -m 755 "$PROJECT_DIR/scripts/launch-omarchy-weather.sh" "$BIN_DIR/omarchy-weather"
install -m 755 "$PROJECT_DIR/scripts/serve-omarchy-weather.py" "$BIN_DIR/serve-omarchy-weather.py"
install -m 755 "$PROJECT_DIR/scripts/waybar-weather.sh" "$BIN_DIR/omarchy-weather-waybar"
if [[ ! -f "$CONFIG_FILE" ]]; then
  install -m 644 "$PROJECT_DIR/config/omarchy-weather.example.json" "$CONFIG_FILE"
fi
for file in waybar-weather-module.jsonc waybar-weather.css; do
  if [[ ! -f "$CONFIG_DIR/$file" ]]; then
    install -m 644 "$PROJECT_DIR/config/$file" "$CONFIG_DIR/$file"
  fi
done
install -Dm 644 "$APP_DIR/icon-192.png" "$ICON_DIR/192x192/apps/omarchy-weather.png"
install -Dm 644 "$APP_DIR/icon-512.png" "$ICON_DIR/512x512/apps/omarchy-weather.png"

cat > "$APPLICATIONS_DIR/omarchy-weather.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Omarchy Weather
Comment=Current conditions and forecasts for your location
Exec="$BIN_DIR/omarchy-weather"
Icon=omarchy-weather
Terminal=false
Categories=Utility;Network;
Keywords=weather;forecast;omarchy;
DESKTOP
chmod 644 "$APPLICATIONS_DIR/omarchy-weather.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi

printf 'Installed Omarchy Weather.\n'
printf '  App files: %s\n' "$APP_DIR"
printf '  Launcher:  %s/omarchy-weather\n' "$BIN_DIR"
printf '  Menu entry: %s/omarchy-weather.desktop\n' "$APPLICATIONS_DIR"
printf '  Waybar:     %s/omarchy-weather-waybar\n' "$BIN_DIR"
printf '  Location:   %s\n' "$CONFIG_FILE"
printf '\nSearch for “Omarchy Weather” in your app launcher, or run: %s/omarchy-weather\n' "$BIN_DIR"
