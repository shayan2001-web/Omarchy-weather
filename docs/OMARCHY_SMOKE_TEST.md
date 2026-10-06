# Omarchy smoke test

Use this checklist on an Omarchy machine to validate the installed launcher and real Waybar integration. It complements `./tests/run.sh`, which uses mocked API responses and a temporary home directory.

## 1. Update, test, and install

From the repository clone on the project branch:

```sh
git pull origin arena/633b0c2a-omarchy-weather
./tests/run.sh
./scripts/install-omarchy.sh
```

The suite requires Bash, Node.js, Python 3, and `jq`. The app launcher requires Python 3; the Waybar command additionally requires `curl` and `jq`. On Arch Linux, install missing tools with:

```sh
sudo pacman -S --needed python nodejs curl jq
```

If this is an existing Waybar setup, follow the configuration merge instructions in the [README](../README.md#optional-waybar-module). The installer preserves existing Waybar snippets; to enable the amber stale-data tint on an older install, merge this rule into the stylesheet Waybar loads:

```css
#custom-weather.stale {
  color: #e5b75b;
}
```

## 2. Check live data and cache creation

Run the installed Waybar command while online:

```sh
~/.local/bin/omarchy-weather-waybar | jq .
```

At least one feed should be available. When both are live, the text includes weather and AQI; the tooltip includes the AQI category and pollutant details. Successful responses are cached in `${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-weather/`.

## 3. Simulate an API outage safely

This test substitutes a temporary `curl` executable for this one command; it does not change your network configuration or the saved cache:

```sh
(
  tmp_curl="$(mktemp -d)"
  trap 'rm -rf -- "$tmp_curl"' EXIT
  cat > "$tmp_curl/curl" <<'SH'
#!/bin/sh
exit 22
SH
  chmod 700 "$tmp_curl/curl"
  PATH="$tmp_curl:$PATH" ~/.local/bin/omarchy-weather-waybar \
    | jq -e '(.text | startswith("~")) and (.class == "stale") and (.tooltip | contains("cached "))'
)
```

A successful check prints the JSON and exits zero. The cached reading should have a `~` marker, the `stale` class, and a saved timestamp in its tooltip. The subshell removes the temporary stub automatically when the command finishes.

## 4. Verify the actual bar

With the module configured, restart Waybar using your normal Omarchy workflow. Confirm that the module renders, its tooltip distinguishes live from cached data, and clicking it opens Omarchy Weather. For a visual stale-state check, temporarily disconnect from the internet and let Waybar refresh; the cached text should have a `~` marker and amber tint. Reconnect and confirm live values return on the next refresh.
