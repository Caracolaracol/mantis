#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Resources/Brand/mantis-head-1024.png"
mkdir -p "$ROOT/build"
WORK="$(mktemp -d "$ROOT/build/icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/Mantis.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/Mantis.icns"
printf 'Icono creado: %s\n' "$ROOT/Resources/Mantis.icns"
