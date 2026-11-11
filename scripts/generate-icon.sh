#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Resources/Brand/mantis-head-1024.png"
mkdir -p "$ROOT/build"
WORK="$(mktemp -d "$ROOT/build/icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/Mantis.iconset"
mkdir -p "$ICONSET"
DOCK_SOURCE="$WORK/mantis-dock-1024.png"
swift "$ROOT/scripts/generate-dock-icon.swift" "$SOURCE" "$DOCK_SOURCE"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$DOCK_SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$DOCK_SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/Mantis.icns"
printf 'Icono creado: %s\n' "$ROOT/Resources/Mantis.icns"
