#!/usr/bin/env bash
# FFNx's run-time files for the iOS app (Resources/ffnx in FF7RecompBundled): the Metal shaders
# (tools/compile_shaders_metal.sh) and FFNx's .toml settings from FFNx/misc. The app copies them
# into its game folder before each game (GameFiles.installRuntime), as the core's Android app carries
# them in assets/ffnx (tools/stage_apk_assets.sh there).
#
#   bash tools/stage_ffnx_runtime.sh       # -> build-ios-ffnx/ffnx
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/external/ff7-recomp-core"
MISC="$CORE/external/FFNx/misc"
OUT="$ROOT/build-ios-ffnx/ffnx"

SHADERS="$CORE/build/shaders"
if ! ls "$SHADERS"/*.mtl.* >/dev/null 2>&1; then
  bash "$ROOT/tools/compile_shaders_metal.sh"
fi

rm -rf "$OUT"
mkdir -p "$OUT/shaders"
cp "$SHADERS"/*.mtl.* "$OUT/shaders/"
cp "$MISC"/FFNx*.toml "$OUT/"
echo "staged $(ls "$OUT/shaders" | wc -l | tr -d ' ') shaders and $(ls "$OUT"/*.toml | wc -l | tr -d ' ') settings files in $OUT"
