# Omarchy Weather

A calm, open-source weather dashboard built with Omarchy Linux in mind. It is a lightweight, installable web app with an optional user-level desktop launcher for Omarchy—no JavaScript framework, build step, or weather API key required.

## What it does

- Shows current conditions, feels-like temperature, today's high and low, sunrise and sunset, and seven-hour and seven-day forecasts.
- Searches worldwide locations and can use the device's location when permission is granted.
- Switches between Celsius and Fahrenheit, remembers the selected location and unit, and saves the last forecast for offline viewing.
- Uses a responsive dark interface with keyboard-friendly city search (`Ctrl` + `K` or `/`).
- Attributes forecast data to [Open-Meteo](https://open-meteo.com/).

## Install on Omarchy

From a clone of this repository, run:

```sh
./scripts/install-omarchy.sh
```

The installer copies the app into `~/.local/share/omarchy-weather`, adds an **Omarchy Weather** entry to your user application menu, and installs the app icons. No root access is needed. This is a browser-backed desktop launcher, not a native GTK binary. Python 3 is required for the small local static-file server; on Arch Linux it is provided by the `python` package.

Launch it from Omarchy's application launcher, or run:

```sh
~/.local/bin/omarchy-weather
```

The launcher uses a Chromium-family browser's app-window mode when available, and otherwise opens the app in your default browser. The local server binds only to `127.0.0.1`. It uses a stable port so your browser's saved location, unit, offline forecast, and service-worker cache persist between launches. If port `47653` is already occupied, close the other service or change `PORT` in `scripts/serve-omarchy-weather.py`, then rerun the installer.

To remove the user-level installation:

```sh
./scripts/uninstall-omarchy.sh
```

## Run locally for development

No build step or package installation is needed. From this directory, run:

```sh
python3 -m http.server 4173 --bind 127.0.0.1
```

Then open <http://127.0.0.1:4173>. Opening `index.html` directly will not enable service-worker or installable-app features. On another local port or an HTTPS host, the app can also be installed from a supported browser's app-install action.

## Weather data

Forecast and city-search requests go directly from the browser to the public Open-Meteo APIs. No account or API key is used. An internet connection is needed for fresh weather and city searches; the last successfully loaded forecast is kept locally so it remains available offline.

## License

The application code is released under the MIT License; see [LICENSE](./LICENSE). Weather data is provided by Open-Meteo and remains subject to its own terms and attribution requirements.
