#!/usr/bin/env bash
set -euo pipefail

API_URL="https://api.open-meteo.com/v1/forecast"
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

weather_json="$(curl \
  --fail \
  --silent \
  --show-error \
  --max-time 10 \
  --get \
  --data-urlencode "latitude=$latitude" \
  --data-urlencode "longitude=$longitude" \
  --data-urlencode 'current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day' \
  --data-urlencode "temperature_unit=$api_temperature_unit" \
  --data-urlencode "wind_speed_unit=$api_wind_unit" \
  --data-urlencode 'timezone=auto' \
  "$API_URL" 2>/dev/null)" || {
  emit_unavailable 'Open-Meteo could not be reached. Check your internet connection.'
  exit 0
}

if ! output="$(jq -cn \
  --arg location "$location" \
  --arg temperature_symbol "$temperature_symbol" \
  --arg wind_symbol "$wind_symbol" \
  --argjson weather "$weather_json" '
    def display_number:
      if type == "number" then round | tostring else "—" end;

    ($weather.current // {}) as $current
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
    | ($current.temperature_2m | display_number) as $temperature
    | ($current.apparent_temperature | display_number) as $feels_like
    | ($current.relative_humidity_2m | display_number) as $humidity
    | ($current.wind_speed_10m | display_number) as $wind_speed
    | (["N","NE","E","SE","S","SW","W","NW"]
       | .[((($current.wind_direction_10m // 0) / 45 | round) % 8)]) as $wind_direction
    | {
        text: "\($condition.icon) \($temperature)°\($temperature_symbol)",
        tooltip: "\($location) · \($condition.label)\nFeels like \($feels_like)°\($temperature_symbol)\nHumidity \($humidity)% · Wind \($wind_direction) \($wind_speed) \($wind_symbol)\nData: Open-Meteo",
        class: $condition.class,
        alt: $condition.label
      }
  ' 2>/dev/null)"; then
  emit_unavailable 'Open-Meteo returned an unreadable forecast.'
  exit 0
fi

printf '%s\n' "$output"
