#!/usr/bin/env bash
# Simulator dev shortcut: point the installed FF7RecompBundled app's Documents/game at this repo's
# game/ folder (your imported Steam files) with a symlink, instead of copying 3+ GB. The simulator
# runs apps as Mac processes, so the link resolves. A device needs a real import (P3 GamePackage).
#
#   bash tools/ios_sim_link_game.sh [simulator-udid]   # default: the only booted simulator
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
BUNDLE_ID=com.ff7recomp.ios.bundled
UDID="${1:-booted}"
GAME="$ROOT/game"
[[ -f "$GAME/ff7_en.exe" ]] || { echo "no $GAME/ff7_en.exe: import your Steam files first (docs/P1_METAL.md)" >&2; exit 1; }
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
mkdir -p "$DATA/Documents"
ln -sfn "$GAME" "$DATA/Documents/game"
echo "linked $DATA/Documents/game -> $GAME"
