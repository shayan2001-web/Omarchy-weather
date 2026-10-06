#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
WAYBAR_DIR="$CONFIG_HOME/waybar"

missing_packages=()
command -v python3 >/dev/null 2>&1 || missing_packages+=(python)
command -v curl >/dev/null 2>&1 || missing_packages+=(curl)
command -v jq >/dev/null 2>&1 || missing_packages+=(jq)
if ((${#missing_packages[@]})); then
  if ! command -v pacman >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
    printf 'Install the missing dependencies first: %s\n' "${missing_packages[*]}" >&2
    exit 1
  fi
  sudo pacman -S --needed "${missing_packages[@]}"
fi

waybar_config="${WAYBAR_CONFIG_FILE:-}"
if [[ -z "$waybar_config" ]]; then
  for candidate in "$WAYBAR_DIR/config.jsonc" "$WAYBAR_DIR/config" "$WAYBAR_DIR/config.json"; do
    if [[ -f "$candidate" ]]; then
      waybar_config="$candidate"
      break
    fi
  done
fi
if [[ -z "$waybar_config" || ! -f "$waybar_config" ]]; then
  printf 'Could not find the active Waybar config. Expected %s/config.jsonc.\n' "$WAYBAR_DIR" >&2
  printf 'Set WAYBAR_CONFIG_FILE to your config path and run this script again.\n' >&2
  exit 1
fi
if [[ -L "$waybar_config" ]]; then
  printf 'Refusing to rewrite symlinked Waybar config: %s\n' "$waybar_config" >&2
  printf 'Edit its target or set WAYBAR_CONFIG_FILE to a regular user config file.\n' >&2
  exit 1
fi

"$PROJECT_DIR/scripts/install-omarchy.sh"

python3 - "$waybar_config" <<'PY'
import json
import os
import shlex
import shutil
import stat
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")


def tokenize(text):
    tokens = []
    comments = []
    index = 0
    decoder = json.JSONDecoder()
    punctuation = set("{}[]:,")
    while index < len(text):
        character = text[index]
        if character.isspace():
            index += 1
            continue
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = len(text) if end < 0 else end
            comments.append((index, end))
            index = end
            continue
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end < 0:
                raise ValueError("Unterminated block comment in Waybar config")
            end += 2
            comments.append((index, end))
            index = end
            continue
        if character == '"':
            try:
                value, end = decoder.raw_decode(text, index)
            except json.JSONDecodeError as error:
                raise ValueError(f"Invalid JSON string in Waybar config: {error}") from error
            tokens.append({"kind": "string", "value": value, "start": index, "end": end})
            index = end
            continue
        if character in punctuation:
            tokens.append({"kind": "punct", "value": character, "start": index, "end": index + 1})
            index += 1
            continue
        start = index
        while index < len(text):
            if text[index].isspace() or text[index] in punctuation or text[index] == '"':
                break
            if text.startswith("//", index) or text.startswith("/*", index):
                break
            index += 1
        if index == start:
            raise ValueError(f"Unsupported character in Waybar config at offset {index}")
        tokens.append({"kind": "atom", "value": text[start:index], "start": start, "end": index})
    return tokens, comments


def analyze(text):
    tokens, comments = tokenize(text)
    if not tokens or tokens[0]["value"] != "{":
        raise ValueError("Waybar config must begin with a JSON object")

    matching = {}
    stack = []
    opening = {"{": "}", "[": "]"}
    closing = {value: key for key, value in opening.items()}
    for token_index, token in enumerate(tokens):
        value = token["value"]
        if token["kind"] != "punct":
            continue
        if value in opening:
            stack.append((value, token_index))
        elif value in closing:
            if not stack or stack[-1][0] != closing[value]:
                raise ValueError("Unbalanced brackets in Waybar config")
            _, open_index = stack.pop()
            matching[open_index] = token_index
            matching[token_index] = open_index
    if stack:
        raise ValueError("Unclosed bracket in Waybar config")

    root_close = matching.get(0)
    if root_close is None:
        raise ValueError("Could not find the end of the Waybar config object")

    properties = []
    index = 1
    while index < root_close:
        if tokens[index]["value"] == ",":
            index += 1
            continue
        key_token = tokens[index]
        if key_token["kind"] != "string" or index + 1 >= root_close or tokens[index + 1]["value"] != ":":
            raise ValueError("Could not safely parse a top-level Waybar config property")
        key = key_token["value"]
        value_index = index + 2
        if value_index >= root_close:
            raise ValueError(f"Missing value for Waybar config key {key!r}")
        value_end = matching.get(value_index, value_index)
        properties.append((key, value_index, value_end, index))
        index = value_end + 1
        if index < root_close and tokens[index]["value"] == ",":
            index += 1
        elif index < root_close:
            raise ValueError("Missing comma between top-level Waybar config properties")

    keys = [key for key, *_ in properties]
    if len(keys) != len(set(keys)):
        raise ValueError("Duplicate top-level keys found; refusing to modify the Waybar config")

    by_key = {key: (value_index, value_end, key_index) for key, value_index, value_end, key_index in properties}
    changes = []
    module_exists = "custom/weather" in by_key
    modules_right_exists = "modules-right" in by_key
    has_weather_module = False

    if modules_right_exists:
        value_index, value_end, _ = by_key["modules-right"]
        if tokens[value_index]["kind"] != "punct" or tokens[value_index]["value"] != "[":
            raise ValueError('"modules-right" is not an array; refusing to modify the Waybar config')
        array_close = matching[value_index]
        items = []
        item_index = value_index + 1
        while item_index < array_close:
            if tokens[item_index]["value"] == ",":
                item_index += 1
                continue
            if tokens[item_index]["kind"] != "string":
                raise ValueError('"modules-right" contains a non-string item; refusing to modify it')
            items.append(tokens[item_index])
            item_index += 1
            if item_index < array_close and tokens[item_index]["value"] != ",":
                raise ValueError('Could not safely parse "modules-right"')
        has_weather_module = any(item["value"] == "custom/weather" for item in items)

        if not has_weather_module:
            open_end = tokens[value_index]["end"]
            close_start = tokens[array_close]["start"]
            if any(start >= open_end and end <= close_start for start, end in comments):
                raise ValueError('Comments inside "modules-right" prevent a safe automatic edit; add "custom/weather" manually')
            newline = "\r\n" if "\r\n" in text else "\n"
            if items:
                first = items[0]
                line_start = text.rfind("\n", 0, first["start"]) + 1
                indent_candidate = text[line_start:first["start"]]
                multiline = newline in text[open_end:close_start]
                indent = indent_candidate if indent_candidate.strip() == "" else "  "
                addition = f'"custom/weather",{newline}{indent}' if multiline else '"custom/weather", '
                changes.append((first["start"], first["start"], addition))
            else:
                interior = text[open_end:close_start]
                if "\n" in interior:
                    line_start = text.rfind("\n", 0, close_start) + 1
                    close_indent = text[line_start:close_start]
                    if close_indent.strip():
                        close_indent = ""
                    item_indent = close_indent + "  "
                    replacement = f'{newline}{item_indent}"custom/weather"{newline}{close_indent}'
                    changes.append((open_end, close_start, replacement))
                else:
                    changes.append((close_start, close_start, '"custom/weather"'))

    additions = []
    if not module_exists:
        waybar_command = shlex.quote(str(Path.home() / ".local/bin/omarchy-weather-waybar"))
        app_command = shlex.quote(str(Path.home() / ".local/bin/omarchy-weather"))
        additions.append(
            '"custom/weather": {\n'
            f'    "exec": {json.dumps(waybar_command)},\n'
            '    "return-type": "json",\n'
            '    "interval": 900,\n'
            f'    "on-click": {json.dumps(app_command)},\n'
            '    "tooltip": true\n'
            '  }'
        )
    if not modules_right_exists:
        additions.append('"modules-right": ["custom/weather"]')

    if additions:
        root_close_token = tokens[root_close]
        last_token = tokens[root_close - 1] if root_close > 1 else tokens[0]
        insert_at = last_token["end"]
        if any(start >= insert_at and end <= root_close_token["start"] for start, end in comments):
            raise ValueError("A trailing comment prevents a safe top-level edit; add the module manually")
        has_properties = bool(properties)
        needs_comma = has_properties and last_token["value"] != ","
        close_line_start = text.rfind("\n", 0, root_close_token["start"]) + 1
        close_indent = text[close_line_start:root_close_token["start"]]
        if close_indent.strip():
            close_indent = ""
        indent = close_indent + "  "
        nested_indent = indent + "  "
        formatted = []
        for addition in additions:
            formatted.append(addition.replace("\n    ", f"\n{nested_indent}").replace("\n  }", f"\n{indent}}}"))
        prefix = "," if needs_comma else ""
        insertion = prefix + "\n" + ("," + "\n").join(indent + item for item in formatted)
        changes.append((insert_at, insert_at, insertion))

    if not changes:
        print('Waybar already has "custom/weather" configured.')
        return

    updated = text
    for start, end, replacement in sorted(changes, key=lambda change: change[0], reverse=True):
        updated = updated[:start] + replacement + updated[end:]

    # Re-parse the edited text before writing anything to disk.
    analyze_updated = tokenize(updated)[0]
    if not analyze_updated or analyze_updated[0]["value"] != "{":
        raise ValueError("Internal config check failed; no file was changed")
    if '"custom/weather"' not in updated:
        raise ValueError("Internal config check failed; no file was changed")

    stamp = __import__("time").strftime("%Y%m%d-%H%M%S")
    backup = path.with_name(path.name + f".backup.{stamp}-{os.getpid()}")
    shutil.copy2(path, backup)
    mode = stat.S_IMODE(path.stat().st_mode)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            file.write(updated)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"Updated Waybar config: {path}")
    print(f"Backup saved: {backup}")


try:
    analyze(source)
except (OSError, ValueError, json.JSONDecodeError) as error:
    print(f"Could not safely update Waybar config: {error}", file=sys.stderr)
    sys.exit(1)
PY

waybar_style="${WAYBAR_STYLE_FILE:-$WAYBAR_DIR/style.css}"
style_source="$PROJECT_DIR/config/waybar-weather.css"
mkdir -p -- "$(dirname -- "$waybar_style")"
if [[ -f "$waybar_style" ]] && grep -q '#custom-weather.stale' "$waybar_style"; then
  printf 'Waybar weather styles are already present in %s.\n' "$waybar_style"
else
  if [[ -f "$waybar_style" ]] && grep -q '#custom-weather' "$waybar_style"; then
    style_addition=$'\n/* Omarchy Weather stale readings */\n#custom-weather.stale {\n  color: #e5b75b;\n}\n'
  else
    style_addition="$(cat -- "$style_source")"
  fi
  if [[ -f "$waybar_style" ]]; then
    style_backup="$waybar_style.backup.$(date +%Y%m%d-%H%M%S)-$$"
    cp -L -- "$waybar_style" "$style_backup"
    printf '\n%s\n' "$style_addition" >> "$waybar_style"
    printf 'Updated Waybar stylesheet: %s\nBackup saved: %s\n' "$waybar_style" "$style_backup"
  else
    printf '%s\n' "$style_addition" > "$waybar_style"
    printf 'Created Waybar stylesheet: %s\n' "$waybar_style"
  fi
fi

if [[ "${OMARCHY_WEATHER_NO_WAYBAR_RESTART:-0}" == 1 ]]; then
  printf 'Waybar restart skipped by request.\n'
elif command -v omarchy-restart-waybar >/dev/null 2>&1; then
  omarchy-restart-waybar
else
  printf 'Configuration is ready. Restart Waybar using your usual Omarchy workflow.\n'
fi

printf '\nTest the module with: %s/.local/bin/omarchy-weather-waybar | jq .\n' "$HOME"
