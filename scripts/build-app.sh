#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EDITION="${MANTIS_MACOS14:-0}"
case "$EDITION" in 0|1) ;; *) printf 'MANTIS_MACOS14 must be 0 or 1\n' >&2; exit 1 ;; esac
if [[ "$EDITION" = 1 ]]; then DEFAULT_APP="$ROOT/build/Mantis-Sonoma.app"; else DEFAULT_APP="$ROOT/build/Mantis.app"; fi
APP="${MANTIS_APP_OUTPUT:-$DEFAULT_APP}"
[[ "$APP" = /* ]] || APP="$PWD/$APP"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
case "$CONFIGURATION" in debug|release) ;; *) printf 'CONFIGURATION must be debug or release\n' >&2; exit 1 ;; esac

ensure_app_closed() {
  local pid running target="$APP/Contents/MacOS/MeetingRecorder"
  for pid in $(/usr/bin/pgrep -x MeetingRecorder || true); do
    running="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    if [[ "$running" = "$target" || ( -f "$running" && -f "$target" && "$running" -ef "$target" ) ]]; then
      printf 'Mantis sigue abierta. Usa Salir en su menú antes de empaquetar; cerrar la ventana no termina la app. No se reemplazará un bundle en ejecución.\n' >&2
      exit 1
    fi
  done
}
ensure_app_closed

cd "$ROOT"
BUILD_ARGS=(-c "$CONFIGURATION" --disable-automatic-resolution)
if [[ "$EDITION" = 1 ]]; then BUILD_ARGS+=(--scratch-path "$ROOT/.build-sonoma"); fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
ensure_app_closed
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/ThirdParty"
cp "$BIN_DIR/MeetingRecorder" "$APP/Contents/MacOS/MeetingRecorder"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ "$EDITION" = 1 ]]; then
  /usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 14.0' "$APP/Contents/Info.plist"
  # Both editions share the source version/build; only target and channel differ.
  /usr/libexec/PlistBuddy -c 'Add :MantisDistributionChannel string sonoma' "$APP/Contents/Info.plist"
fi
cp "$ROOT/Resources/Mantis.icns" "$APP/Contents/Resources/Mantis.icns"
cp "$ROOT/Resources/MantisTemplate.png" "$APP/Contents/Resources/MantisTemplate.png"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/Sources/MeetingCore/Resources/English.json" "$APP/Contents/Resources/English.json"
swift "$ROOT/scripts/generate-localizations.swift" "$APP/Contents/Resources"
plutil -lint "$APP/Contents/Info.plist"
ditto "$BIN_DIR/CTranscribe.framework" "$APP/Contents/Frameworks/CTranscribe.framework"
cp "$ROOT/Resources/ThirdParty/"* "$APP/Contents/Resources/ThirdParty/"
# SwiftPM's development RPATH must not be required on another computer.
while IFS= read -r path; do
  case "$path" in "$ROOT"/*) install_name_tool -delete_rpath "$path" "$APP/Contents/MacOS/MeetingRecorder" ;; esac
done < <(otool -l "$APP/Contents/MacOS/MeetingRecorder" | awk '$1 == "cmd" && $2 == "LC_RPATH" { found=1; next } found && $1 == "path" { print $2; found=0 }')
install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/MeetingRecorder"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP/Contents/Frameworks/CTranscribe.framework"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --strict "$APP"
printf '\nApp creada (no instalada ni abierta):\n%s\n' "$APP"
