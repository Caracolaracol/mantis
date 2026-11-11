#!/bin/bash
set -euo pipefail
umask 077

APP="${MEETING_RECORDER_APP:-/Applications/Mantis.app}"
EXECUTABLE="$APP/Contents/MacOS/MeetingRecorder"
CONTROL="${MEETING_RECORDER_CONTROL:-$HOME/Library/Application Support/MeetingRecorder/Control}"
STATUS="$CONTROL/status.json"
NAME="${NAME:-meeting_recorder}"
if [[ "${MEETING_RECORDER_DRY_RUN:-0}" != 1 ]]; then
  SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}"
  [[ -n "$SKETCHYBAR_BIN" ]] || SKETCHYBAR_BIN=/opt/homebrew/bin/sketchybar
  [[ -x "$SKETCHYBAR_BIN" ]] || SKETCHYBAR_BIN=/usr/local/bin/sketchybar
  [[ -x "$SKETCHYBAR_BIN" ]] || { printf 'No se encuentra SketchyBar; configura SKETCHYBAR_BIN.\n' >&2; exit 1; }
fi
STATE=offline
ELAPSED=0
LANGUAGE=en

if [[ -f "$STATUS" ]]; then
  LANGUAGE=$(/usr/bin/plutil -extract language raw -o - "$STATUS" 2>/dev/null || true)
  [[ "$LANGUAGE" == es ]] || LANGUAGE=en
  PID=$(/usr/bin/plutil -extract pid raw -o - "$STATUS" 2>/dev/null || true)
  STAMP=$(/usr/bin/plutil -extract updatedAt raw -o - "$STATUS" 2>/dev/null || true)
  if [[ "$PID" =~ ^[0-9]+$ && "$STAMP" =~ ^[0-9]+(\.[0-9]+)?$ ]] && kill -0 "$PID" 2>/dev/null; then
    AGE=$(( $(date +%s) - ${STAMP%.*} ))
    if (( AGE >= 0 && AGE <= 5 )); then
      STATE=$(/usr/bin/plutil -extract state raw -o - "$STATUS" 2>/dev/null || true)
      ELAPSED=$(/usr/bin/plutil -extract elapsedSeconds raw -o - "$STATUS" 2>/dev/null || printf '0')
    fi
  fi
fi
[[ "$ELAPSED" =~ ^[0-9]+$ ]] || ELAPSED=0

if [[ "${1:-}" == click || "${SENDER:-}" == mouse.clicked ]]; then
  COMMAND=--toggle-recording
  if [[ "${BUTTON:-left}" == right || "$STATE" == error ]]; then
    COMMAND=--show
  fi
  # A busy left click must neither raise the library nor queue a later recording.
  if [[ "${BUTTON:-left}" != right && ( "$STATE" == preparing || "$STATE" == transcribing ) ]]; then
    if [[ "${MEETING_RECORDER_DRY_RUN:-0}" == 1 ]]; then printf 'Busy; no command sent\n'; fi
    exit 0
  fi
  if [[ "${MEETING_RECORDER_DRY_RUN:-0}" == 1 ]]; then
    printf 'Would send %s to %s\n' "$COMMAND" "$EXECUTABLE"
    exit 0
  fi
  if [[ ! -x "$EXECUTABLE" ]]; then
    MISSING='Missing app'
    [[ "$LANGUAGE" != es ]] || MISSING='Falta app'
    "$SKETCHYBAR_BIN" --set "$NAME" label="$MISSING" icon.color=0xffde7f26
    exit 1
  fi
  mkdir -p "$CONTROL"
  "$EXECUTABLE" "$COMMAND" >/dev/null 2>>"$CONTROL/launcher.log" &
  exit 0
fi

COLOR=0xff9b7fd4
LABEL_COLOR=0xffccd7e4
ICON='●'
LABEL=Record
[[ "$LANGUAGE" != es ]] || LABEL=Grabar
case "$STATE" in
  recording)
    ICON='●'; COLOR=0xffd94a6d
    printf -v LABEL 'REC %02d:%02d' "$((ELAPSED / 60))" "$((ELAPSED % 60))"
    ;;
  preparing) LABEL='Preparing'; [[ "$LANGUAGE" != es ]] || LABEL='Preparando'; COLOR=0xffde7f26 ;;
  transcribing) LABEL='Transcribing'; [[ "$LANGUAGE" != es ]] || LABEL='Transcribiendo'; COLOR=0xffde7f26 ;;
  error) LABEL='Review'; [[ "$LANGUAGE" != es ]] || LABEL='Revisar'; COLOR=0xffde7f26 ;;
esac
if [[ "$STATE" == recording || "$STATE" == preparing || "$STATE" == transcribing || "$STATE" == error ]]; then
  LABEL_COLOR="$COLOR"
fi

if [[ "${MEETING_RECORDER_DRY_RUN:-0}" == 1 ]]; then
  printf 'state=%s label=%s label_color=%s\n' "$STATE" "$LABEL" "$LABEL_COLOR"
else
  "$SKETCHYBAR_BIN" --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$LABEL" label.color="$LABEL_COLOR"
fi
