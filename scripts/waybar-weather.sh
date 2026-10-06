#!/usr/bin/env bash
set -euo pipefail

WEATHER_API="https://api.open-meteo.com/v1/forecast"
AIR_QUALITY_API="https://air-quality-api.open-meteo.com/v1/air-quality"
CONFIG_FILE="${OMARCHY_WEATHER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-weather/config.json}"

emit_unavailable() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg reason "$reason" '{text:"Weather --",tooltip:$reason,class:"unavailable",alt:"Weather unavailable"}'
  else
    printf '{"text":"Weather --","tooltip":"Install curl and jq to enable the Waybar weather module.","class":"unavailable","alt":"Weather unavailable"}\n'
  fi
}

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  emit_unavailable 'Install curl and jq to enable the Waybar weather module.'
  exit 0
fi

latitude='33.6844'
longitude='73.0479'
location='Islamabad'
unit='c'

if [[ -f "$CONFIG_FILE" ]]; then
  latitude="$(jq -er '.latitude | select(type == "number" and . >= -90 and . <= 90)' "$CONFIG_FILE" 2>/dev/null)" || {
    emit_unavailable "Invalid latitude in $CONFIG_FILE."
    exit 0
  }
  longitude="$(jq -er '.longitude | select(type == "number" and . >= -180 and . <= 180)' "$CONFIG_FILE" 2>/dev/null)" || {
    emit_unavailable "Invalid longitude in $CONFIG_FILE."
    exit 0
  }
  location="$(jq -er '(.location // "Islamabad") | select(type == "string" and length > 0)' "$CONFIG_FILE" 2>/dev/null)" || {
    emit_unavailable "Invalid location name in $CONFIG_FILE."
    exit 0
  }
  unit="$(jq -r '(.unit // "c") | ascii_downcase' "$CONFIG_FILE" 2>/dev/null)" || {
    emit_unavailable "Could not read settings in $CONFIG_FILE."
    exit 0
  }
fi

case "$unit" in
  c|celsius)
    api_temperature_unit='celsius'
    temperature_symbol='C'
    api_wind_unit='kmh'
    wind_symbol='km/h'
    ;;
  f|fahrenheit)
    api_temperature_unit='fahrenheit'
    temperature_symbol='F'
    api_wind_unit='mph'
    wind_symbol='mph'
    ;;
  *)
    emit_unavailable "Set unit to c or f in $CONFIG_FILE."
    exit 0
    ;;
esac

request_dir="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-weather-waybar.XXXXXX")"
trap 'rm -rf -- "$request_dir"' EXIT
weather_file="$request_dir/weather.json"
air_quality_file="$request_dir/air-quality.json"

curl \
  --fail --silent --show-error --max-time 10 --get \
  --data-urlencode "latitude=$latitude" \
  --data-urlencode "longitude=$longitude" \
  --data-urlencode 'current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day' \
  --data-urlencode "temperature_unit=$api_temperature_unit" \
  --data-urlencode "wind_speed_unit=$api_wind_unit" \
  --data-urlencode 'timezone=auto' \
  --output "$weather_file" \
  "$WEATHER_API" 2>/dev/null &
weather_pid=$!

curl \
  --fail --silent --show-error --max-time 10 --get \
  --data-urlencode "latitude=$latitude" \
  --data-urlencode "longitude=$longitude" \
  --data-urlencode 'current=us_aqi,pm2_5,pm10,ozone,nitrogen_dioxide' \
  --data-urlencode 'timezone=auto' \
  --output "$air_quality_file" \
  "$AIR_QUALITY_API" 2>/dev/null &
air_quality_pid=$!

weather_available=false
if wait "$weather_pid" && jq -e '(.current | type == "object") and (.current.temperature_2m | type == "number")' "$weather_file" >/dev/null 2>&1; then
  weather_available=true
  weather_json="$(cat "$weather_file")"
else
  weather_json='{}'
fi

air_quality_available=false
if wait "$air_quality_pid" && jq -e '(.current | type == "object") and (.current.us_aqi | type == "number")' "$air_quality_file" >/dev/null 2>&1; then
  air_quality_available=true
  air_quality_json="$(cat "$air_quality_file")"
else
  air_quality_json='{}'
fi

if [[ "$weather_available" == false && "$air_quality_available" == false ]]; then
  emit_unavailable 'Weather and air-quality services are unavailable. Check your connection.'
  exit 0
fi

if ! output="$(jq -cn \
  --arg location "$location" \
  --arg temperature_symbol "$temperature_symbol" \
  --arg wind_symbol "$wind_symbol" \
  --argjson weather_available "$weather_available" \
  --argjson air_quality_available "$air_quality_available" \
  --argjson weather "$weather_json" \
  --argjson air_quality "$air_quality_json" '
    def display_number:
      if type == "number" then round | tostring else "—" end;

    def air_level($value):
      if $value <= 50 then {label:"Good", class:"good"}
      elif $value <= 100 then {label:"Moderate", class:"moderate"}
      elif $value <= 150 then {label:"Unhealthy for sensitive groups", class:"sensitive"}
      elif $value <= 200 then {label:"Unhealthy", class:"unhealthy"}
      elif $value <= 300 then {label:"Very unhealthy", class:"very-unhealthy"}
      else {label:"Hazardous", class:"hazardous"} end;

    ($weather.current // {}) as $current
    | ($air_quality.current // {}) as $air
    | ($weather_available and ($current.temperature_2m | type == "number")) as $has_weather
    | ($air_quality_available and ($air.us_aqi | type == "number")) as $has_air_quality
    | ($current.weather_code // -1) as $code
    | ($current.is_day // 1) as $day
    | (
        if $code == 0 then
          if $day == 0 then {icon:"☾", label:"Clear night", class:"clear"}
          else {icon:"☀", label:"Clear sky", class:"clear"} end
        elif $code == 1 then {icon:"◐", label:"Mainly clear", class:"partly-cloudy"}
        elif $code == 2 then {icon:"◐", label:"Partly cloudy", class:"partly-cloudy"}
        elif $code == 3 then {icon:"☁", label:"Overcast", class:"cloudy"}
        elif $code == 45 or $code == 48 then {icon:"≋", label:"Fog", class:"fog"}
        elif ([51,53,55,56,57] | index($code)) then {icon:"☂", label:"Drizzle", class:"rain"}
        elif ([61,63,65,66,67,80,81,82] | index($code)) then {icon:"☂", label:"Rain", class:"rain"}
        elif ([71,73,75,77,85,86] | index($code)) then {icon:"❄", label:"Snow", class:"snow"}
        elif ([95,96,99] | index($code)) then {icon:"ϟ", label:"Thunderstorm", class:"storm"}
        else {icon:"·", label:"Mixed conditions", class:"cloudy"} end
      ) as $condition
    | (if $has_air_quality then ($air.us_aqi | round | tostring) else "" end) as $aqi
    | (if $has_air_quality then air_level($air.us_aqi) else {label:"Unavailable", class:"unavailable"} end) as $air_level
    | (if $has_weather then ($current.temperature_2m | display_number) else "—" end) as $temperature
    | (if $has_weather then ($current.apparent_temperature | display_number) else "—" end) as $feels_like
    | (if $has_weather then ($current.relative_humidity_2m | display_number) else "—" end) as $humidity
    | (if $has_weather then ($current.wind_speed_10m | display_number) else "—" end) as $wind_speed
    | (["N","NE","E","SE","S","SW","W","NW"]
       | .[((($current.wind_direction_10m // 0) / 45 | round) % 8)]) as $wind_direction
    | ($air.pm2_5 | display_number) as $pm25
    | ($air.pm10 | display_number) as $pm10
    | ($air.ozone | display_number) as $ozone
    | ($air.nitrogen_dioxide | display_number) as $nitrogen_dioxide
    | (if $has_weather then "\($condition.icon) \($temperature)°\($temperature_symbol)" else "" end) as $weather_text
    | (if $has_weather and $has_air_quality then "\($weather_text) · AQI \($aqi)"
       elif $has_weather then $weather_text
       elif $has_air_quality then "AQI \($aqi)"
       else "Weather --" end) as $text
    | ([
        if $has_weather then "\($location) · \($condition.label)" else "\($location) · Current weather unavailable" end,
        (if $has_weather then "Feels like \($feels_like)°\($temperature_symbol)" else null end),
        (if $has_weather then "Humidity \($humidity)% · Wind \($wind_direction) \($wind_speed) \($wind_symbol)" else null end),
        (if $has_air_quality then "US AQI \($aqi) · \($air_level.label)" else "Air-quality data unavailable" end),
        (if $has_air_quality then "PM2.5 \($pm25) · PM10 \($pm10) µg/m³" else null end),
        (if $has_air_quality then "O₃ \($ozone) · NO₂ \($nitrogen_dioxide) µg/m³" else null end),
        (if $has_weather then "Weather data: Open-Meteo" else null end),
        (if $has_air_quality then "Air-quality data: Open-Meteo · CAMS" else null end)
      ] | map(select(. != null)) | join("\n")) as $tooltip
    | {
        text: $text,
        tooltip: $tooltip,
        class: (if $has_weather then $condition.class else "unavailable" end),
        alt: (if $has_weather and $has_air_quality then "\($condition.label), US AQI \($aqi), \($air_level.label)"
              elif $has_weather then $condition.label
              elif $has_air_quality then "US AQI \($aqi), \($air_level.label)"
              else "Weather unavailable" end)
      }
  ' 2>/dev/null)"; then
  emit_unavailable 'Open-Meteo returned unreadable weather or air-quality data.'
  exit 0
fi

printf '%s\n' "$output"
