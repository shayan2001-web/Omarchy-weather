#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-waybar-tests.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
MOCK_BIN="$TEMP_DIR/bin"
CONFIG_FILE="$TEMP_DIR/config.json"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

output_file=''
endpoint=''
expect_output_file=false
for argument in "$@"; do
  if [[ "$expect_output_file" == true ]]; then
    output_file="$argument"
    expect_output_file=false
    continue
  fi
  case "$argument" in
    --output)
      expect_output_file=true
      ;;
    https://api.open-meteo.com/v1/forecast|https://air-quality-api.open-meteo.com/v1/air-quality)
      endpoint="$argument"
      ;;
  esac
done

[[ -n "$output_file" && -n "$endpoint" ]]
case "$endpoint" in
  https://api.open-meteo.com/v1/forecast)
    case "${WAYBAR_TEST_CASE:?}" in
      both|weather-only)
        cat > "$output_file" <<'JSON'
{"current":{"temperature_2m":24.4,"apparent_temperature":25.1,"relative_humidity_2m":52,"weather_code":61,"wind_speed_10m":10,"wind_direction_10m":90,"is_day":1}}
JSON
        ;;
      *) exit 22 ;;
    esac
    ;;
  https://air-quality-api.open-meteo.com/v1/air-quality)
    case "${WAYBAR_TEST_CASE:?}" in
      both|aqi-only)
        cat > "$output_file" <<'JSON'
{"current":{"us_aqi":156,"pm2_5":66.6,"pm10":80.2,"ozone":40.1,"nitrogen_dioxide":16.4}}
JSON
        ;;
      *) exit 22 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod 755 "$MOCK_BIN/curl"
printf '{"latitude": 33.6844, "longitude": 73.0479, "location": "Test City", "unit": "c"}\n' \
  > "$CONFIG_FILE"

assert_json() {
  local expression="$1"
  jq -e "$expression" <<<"$result" >/dev/null || {
    printf 'Waybar output did not match: %s\n%s\n' "$expression" "$result" >&2
    return 1
  }
}

run_case() {
  local scenario="$1"
  local expected_text="$2"
  local assertions="$3"
  local cache_dir="${4:-$TEMP_DIR/cache-$scenario}"
  result="$(
    PATH="$MOCK_BIN:$PATH" \
    WAYBAR_TEST_CASE="$scenario" \
    OMARCHY_WEATHER_CONFIG="$CONFIG_FILE" \
    XDG_CACHE_HOME="$cache_dir" \
      "$ROOT_DIR/scripts/waybar-weather.sh"
  )"
  jq -e --arg expected "$expected_text" '.text == $expected' <<<"$result" >/dev/null || {
    printf 'Unexpected Waybar text for %s: %s\n' "$scenario" "$result" >&2
    return 1
  }
  assert_json "$assertions"
}

# Verify the live and independent-failure output without a cache.
run_case both '☂ 24°C · AQI 156' \
  '(.class == "rain") and (.tooltip | contains("US AQI 156 · Unhealthy")) and (.tooltip | contains("PM2.5 67 · PM10 80 µg/m³")) and (.tooltip | contains("O₃ 40 · NO₂ 16 µg/m³"))'
run_case weather-only '☂ 24°C' \
  '(.class == "rain") and (.tooltip | contains("Air-quality data unavailable")) and (.tooltip | contains("Weather data: Open-Meteo · live"))'
run_case aqi-only 'AQI 156' \
  '(.class == "unavailable") and (.tooltip | contains("Current weather unavailable")) and (.tooltip | contains("US AQI 156 · Unhealthy"))'
run_case neither 'Weather --' \
  '(.class == "unavailable") and (.tooltip | contains("Weather and air-quality services are unavailable"))'

# Seed a per-location/unit cache, then verify each feed can go stale independently.
OFFLINE_CACHE_DIR="$TEMP_DIR/offline-cache"
run_case both '☂ 24°C · AQI 156' \
  '(.tooltip | contains("Weather data: Open-Meteo · live")) and (.tooltip | contains("Air-quality data: Open-Meteo · CAMS · live"))' \
  "$OFFLINE_CACHE_DIR"
CACHE_FILE="$OFFLINE_CACHE_DIR/omarchy-weather/waybar-33.6844-73.0479-c.json"
[[ -f "$CACHE_FILE" ]]
jq -e '.weather.data.current.temperature_2m == 24.4 and .air_quality.data.current.us_aqi == 156' \
  "$CACHE_FILE" >/dev/null
[[ "$(stat -c '%a' "$OFFLINE_CACHE_DIR/omarchy-weather")" == 700 ]]
[[ "$(stat -c '%a' "$CACHE_FILE")" == 600 ]]

run_case weather-only '~☂ 24°C · AQI 156' \
  '(.class == "stale") and (.tooltip | contains("Weather data: Open-Meteo · live")) and (.tooltip | contains("Air-quality data: Open-Meteo · CAMS · cached ")) and (.tooltip | contains("Live data unavailable · showing saved values where needed"))' \
  "$OFFLINE_CACHE_DIR"
run_case aqi-only '~☂ 24°C · AQI 156' \
  '(.class == "stale") and (.tooltip | contains("Weather data: Open-Meteo · cached ")) and (.tooltip | contains("Air-quality data: Open-Meteo · CAMS · live"))' \
  "$OFFLINE_CACHE_DIR"
run_case neither '~☂ 24°C · AQI 156' \
  '(.class == "stale") and (.alt | contains("cached data")) and (.tooltip | contains("Weather data: Open-Meteo · cached ")) and (.tooltip | contains("Air-quality data: Open-Meteo · CAMS · cached "))' \
  "$OFFLINE_CACHE_DIR"

# A different coordinate or unit must not reuse the saved response.
cat > "$CONFIG_FILE" <<'JSON'
{"latitude":34,"longitude":73.0479,"location":"Other City","unit":"c"}
JSON
run_case neither 'Weather --' \
  '(.class == "unavailable") and (.tooltip | contains("Weather and air-quality services are unavailable"))' \
  "$OFFLINE_CACHE_DIR"
cat > "$CONFIG_FILE" <<'JSON'
{"latitude":33.6844,"longitude":73.0479,"location":"Test City","unit":"f"}
JSON
run_case neither 'Weather --' \
  '(.class == "unavailable") and (.tooltip | contains("Weather and air-quality services are unavailable"))' \
  "$OFFLINE_CACHE_DIR"

cat > "$CONFIG_FILE" <<'JSON'
{"latitude":91,"longitude":73,"location":"Invalid","unit":"c"}
JSON
result="$(
  PATH="$MOCK_BIN:$PATH" \
  WAYBAR_TEST_CASE=both \
  OMARCHY_WEATHER_CONFIG="$CONFIG_FILE" \
  XDG_CACHE_HOME="$TEMP_DIR/invalid-cache" \
    "$ROOT_DIR/scripts/waybar-weather.sh"
)"
assert_json '(.text == "Weather --") and (.tooltip | contains("Invalid latitude"))'
printf 'Passed: live Waybar output, feed failures, offline cache/freshness, location isolation, and invalid config.\n'
