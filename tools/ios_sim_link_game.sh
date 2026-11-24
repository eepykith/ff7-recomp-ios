#!/usr/bin/env bash
# Simulator dev shortcut: point the installed app's game folder
# (Library/Application Support/FF7Recomp/game) at this repo's game/ folder (your imported Steam
# files) with a symlink, instead of copying 3+ GB. The simulator runs apps as Mac processes, so
# the link resolves. On an iPhone the app gets its files itself (Game files in the launcher).
#
#   bash tools/ios_sim_link_game.sh [simulator-udid]   # default: the only booted simulator
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
BUNDLE_ID=com.ff7recomp.ios
UDID="${1:-booted}"
GAME="$ROOT/game"
[[ -f "$GAME/ff7_en.exe" ]] || { echo "no $GAME/ff7_en.exe: import your Steam files first (README step 2)" >&2; exit 1; }
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
mkdir -p "$DATA/Library/Application Support/FF7Recomp"
ln -sfn "$GAME" "$DATA/Library/Application Support/FF7Recomp/game"
echo "linked $DATA/Library/Application Support/FF7Recomp/game -> $GAME"
