#!/bin/bash
set -euo pipefail
umask 077

APP="${MEETING_RECORDER_APP:-$HOME/Code/meeting-recorder/build/Mantis.app}"
EXECUTABLE="$APP/Contents/MacOS/MeetingRecorder"
CONTROL="${MEETING_RECORDER_CONTROL:-$HOME/Library/Application Support/MeetingRecorder/Control}"
STATUS="$CONTROL/status.json"
NAME="${NAME:-meeting_recorder}"
STATE=offline
ELAPSED=0

if [[ -f "$STATUS" ]]; then
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

if [[ "${1:-}" == click ]]; then
  COMMAND=--toggle-recording
  if [[ "${BUTTON:-left}" == right || "$STATE" == preparing || "$STATE" == transcribing || "$STATE" == error ]]; then
    COMMAND=--show
  fi
  if [[ "${MEETING_RECORDER_DRY_RUN:-0}" == 1 ]]; then
    printf 'Would send %s to %s\n' "$COMMAND" "$EXECUTABLE"
    exit 0
  fi
  if [[ ! -x "$EXECUTABLE" ]]; then
    /opt/homebrew/bin/sketchybar --set "$NAME" label='Falta app' icon.color=0xffde7f26
    exit 1
  fi
  mkdir -p "$CONTROL"
  "$EXECUTABLE" "$COMMAND" >/dev/null 2>>"$CONTROL/launcher.log" &
  exit 0
fi

COLOR=0xff9b7fd4
LABEL_COLOR=0xffccd7e4
ICON='󰑋'
LABEL=Grabar
case "$STATE" in
  recording)
    ICON='●'; COLOR=0xffd94a6d
    printf -v LABEL 'REC %02d:%02d' "$((ELAPSED / 60))" "$((ELAPSED % 60))"
    ;;
  preparing) LABEL='Preparando'; COLOR=0xffde7f26 ;;
  transcribing) LABEL='Transcribiendo'; COLOR=0xffde7f26 ;;
  error) LABEL='Revisar'; COLOR=0xffde7f26 ;;
esac
if [[ "$STATE" == recording || "$STATE" == preparing || "$STATE" == transcribing || "$STATE" == error ]]; then
  LABEL_COLOR="$COLOR"
fi

if [[ "${MEETING_RECORDER_DRY_RUN:-0}" == 1 ]]; then
  printf 'state=%s label=%s label_color=%s\n' "$STATE" "$LABEL" "$LABEL_COLOR"
else
  /opt/homebrew/bin/sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$LABEL" label.color="$LABEL_COLOR"
fi
