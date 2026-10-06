# Omarchy Weather

A calm, open-source weather dashboard built with Omarchy Linux in mind. It is a lightweight, installable web app with an optional user-level desktop launcher and Waybar module. It needs no JavaScript framework or build step; personal, non-commercial use needs no weather API key.

## What it does

- Shows current conditions, feels-like temperature, today's high and low, sunrise and sunset, and seven-hour and seven-day forecasts.
- Displays a model-based U.S. AQI with PM2.5, PM10, ozone, and nitrogen-dioxide readings.
- Searches worldwide locations and can use the device's location when permission is granted.
- Switches between Celsius and Fahrenheit, remembers the selected location and unit, and saves the last forecast for offline viewing.
- Uses a responsive dark interface with keyboard-friendly city search (`Ctrl` + `K` or `/`).
- Attributes forecast data to [Open-Meteo](https://open-meteo.com/).

## Install on Omarchy

From a clone of this repository, run:

```sh
./scripts/install-omarchy.sh
```

The installer copies the app into `~/.local/share/omarchy-weather`, adds an **Omarchy Weather** entry to your user application menu, installs the app icons and Waybar command, and creates a default location file at `~/.config/omarchy-weather/config.json` if one does not already exist. No root access is needed. The desktop launcher is browser-backed, not a native GTK binary. Python 3 is required for its small local static-file server; on Arch Linux it is provided by the `python` package.

Launch the app from Omarchy's application launcher, or run:

```sh
~/.local/bin/omarchy-weather
```

The launcher uses a Chromium-family browser's app-window mode when available, and otherwise opens the app in your default browser. The local server binds only to `127.0.0.1`. It uses a stable port so browser preferences, saved forecasts, and the service-worker cache persist between launches. If port `47653` is already occupied, close the other service or change `PORT` in `scripts/serve-omarchy-weather.py`, then rerun the installer.

## Optional Waybar module

The installer adds `~/.local/bin/omarchy-weather-waybar`. The module reads `~/.config/omarchy-weather/config.json`, fetches current conditions every 15 minutes when Waybar runs it, and opens the desktop app when clicked. It needs `curl` and `jq`; if either is missing, the module displays an explanatory unavailable state. Install them on Arch Linux if needed:

```sh
sudo pacman -S curl jq
```

Edit the location and unit in `~/.config/omarchy-weather/config.json` (`unit` can be `c` or `f`). The Waybar module uses this file independently of the city and unit selected inside the browser app.

Merge `~/.config/omarchy-weather/waybar-weather-module.jsonc` into your existing Waybar config, and add `"custom/weather"` to its `modules-right` array. Append `~/.config/omarchy-weather/waybar-weather.css` to your Waybar stylesheet, then restart Waybar. If Waybar cannot find commands in `~/.local/bin`, use their full paths in the module configuration.

## Uninstall

```sh
./scripts/uninstall-omarchy.sh
```

The uninstall script removes the user-level app, menu entry, icons, and Waybar command. It deliberately leaves `~/.config/omarchy-weather/`—including your location settings and copied Waybar snippets—in place.

## Run locally for development

No build step or package installation is needed. From this directory, run:

```sh
python3 -m http.server 4173 --bind 127.0.0.1
```

Then open <http://127.0.0.1:4173>. Opening `index.html` directly will not enable service-worker or installable-app features. On another local port or an HTTPS host, the app can also be installed from a supported browser's app-install action.

## Weather data

The dashboard requests weather forecasts, air-quality estimates, and city-search results directly from Open-Meteo; the Waybar module requests current weather from the same provider. No API key is needed for personal, non-commercial use. Air-quality estimates are based on CAMS models, not local station measurements. Open-Meteo's air-quality API is for non-commercial use under 10,000 daily calls; review the [provider terms](https://open-meteo.com/en/terms) before commercial deployment. An internet connection is needed for fresh data and city searches; the last successful weather and air-quality responses are saved locally for offline viewing.

## License

The application code is released under the MIT License; see [LICENSE](./LICENSE). Weather data is provided by Open-Meteo and remains subject to its own terms and attribution requirements.
