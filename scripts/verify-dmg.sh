#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/build/Mantis.app/Contents/Info.plist")"
IMAGE="${1:-$ROOT/build/Mantis-$VERSION.dmg}"
[[ -f "$IMAGE" ]] || { printf 'No existe el DMG: %s\n' "$IMAGE" >&2; exit 1; }
TEMP_ROOT="${MANTIS_PACKAGE_TEMP:-${TMPDIR:-/private/tmp}/opencode}"
mkdir -p "$TEMP_ROOT"
WORK="$(mktemp -d "$TEMP_ROOT/mantis-dmg-check.XXXXXX")"
MOUNT="$WORK/volume"
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" = 1 ]]; then
    hdiutil detach "$MOUNT" >/dev/null || { printf 'No se pudo desmontar %s; se conserva el temporal.\n' "$MOUNT" >&2; return; }
  fi
  case "$WORK" in "$TEMP_ROOT"/mantis-dmg-check.*) rm -rf -- "$WORK" ;; esac
}
trap cleanup EXIT
mkdir "$MOUNT"
hdiutil verify "$IMAGE"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$IMAGE"
MOUNTED=1
[[ -d "$MOUNT/Mantis.app" && -L "$MOUNT/Aplicaciones" ]] || { printf 'Faltan los elementos para instalar arrastrando.\n' >&2; exit 1; }
[[ "$(readlink "$MOUNT/Aplicaciones")" = /Applications ]] || { printf 'Destino de Aplicaciones incorrecto.\n' >&2; exit 1; }
codesign --verify --deep --strict "$MOUNT/Mantis.app"
printf '\nMotor dentro del DMG: '
"$MOUNT/Mantis.app/Contents/MacOS/MeetingRecorder" --engine-version
printf 'Arquitecturas: '
lipo -archs "$MOUNT/Mantis.app/Contents/MacOS/MeetingRecorder"
printf 'Validado: Mantis.app + acceso a /Applications, solo lectura; no se instaló ni se inició la GUI.\n'
