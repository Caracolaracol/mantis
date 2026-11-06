#!/bin/bash
# Run this file from sketchybarrc, after installing the plugin described in README.md.
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
PLUGIN="${MANTIS_WIDGET_SCRIPT:-$CONFIG_DIR/plugins/mantis-recorder.sh}"
APP="${MANTIS_APP_PATH:-/Applications/Mantis.app}"
ITEM="${MANTIS_WIDGET_NAME:-mantis}"
POSITION="${MANTIS_WIDGET_POSITION:-right}"
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}"
[[ -n "$SKETCHYBAR_BIN" ]] || SKETCHYBAR_BIN=/opt/homebrew/bin/sketchybar
[[ -x "$SKETCHYBAR_BIN" ]] || SKETCHYBAR_BIN=/usr/local/bin/sketchybar
[[ -x "$SKETCHYBAR_BIN" ]] || { printf 'No se encuentra SketchyBar; configura SKETCHYBAR_BIN.\n' >&2; exit 1; }
[[ -f "$PLUGIN" ]] || { printf 'Falta el plugin Mantis: %s\n' "$PLUGIN" >&2; exit 1; }

# Quote every argument, including paths containing spaces. SketchyBar launches
# this command separately, so exports in sketchybarrc alone are not sufficient.
printf -v COMMAND '%q ' /usr/bin/env "MEETING_RECORDER_APP=$APP" "SKETCHYBAR_BIN=$SKETCHYBAR_BIN" /bin/bash "$PLUGIN"

"$SKETCHYBAR_BIN" --add item "$ITEM" "$POSITION" \
  --set "$ITEM" icon='●' label='Record' \
    icon.color=0xff9b7fd4 label.color=0xffccd7e4 \
    update_freq=1 updates=on script="$COMMAND" \
  --subscribe "$ITEM" mouse.clicked system_woke
