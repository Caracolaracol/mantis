#!/bin/bash
set -euo pipefail

# Separate, opt-in artifact. Never replace the standard bundle or its DMG.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${MANTIS_APP_OUTPUT:-$ROOT/build/Mantis-Sonoma.app}"
MANTIS_MACOS14=1 MANTIS_APP_OUTPUT="$APP" CONFIGURATION="${CONFIGURATION:-release}" bash "$ROOT/scripts/build-app.sh"
MANTIS_APP="$APP" bash "$ROOT/scripts/build-dmg.sh" "$@"
