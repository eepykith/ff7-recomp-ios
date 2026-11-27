#!/usr/bin/env bash
# Compile FFNx shaders for bgfx Metal (*.mtl.*) into game/shaders and ./shaders.
# Requires: make -C external/ff7-recomp-core/external/bgfx shaderc
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/external/ff7-recomp-core"
SHADERC="${SHADERC:-$CORE/external/bgfx/tools/bin/darwin/shaderc}"
SRC="$CORE/external/FFNx/misc"
INC="$CORE/build/shader_include"
OUT="$CORE/build/shaders"
test -x "$SHADERC" || { echo "build shaderc first: make -C $CORE/external/bgfx shaderc" >&2; exit 1; }
mkdir -p "$INC/bgfx" "$OUT" "$ROOT/game/shaders" "$ROOT/shaders" "$CORE/game/shaders"
cp "$CORE"/external/bgfx/src/bgfx_*.sh "$INC/bgfx/"
SHADERS=(FFNx FFNx.lighting FFNx.shadowmap FFNx.field.shadow FFNx.overlay FFNx.post FFNx.post.ntscj FFNx.blit FFNx.yuvmovie FFNx.yuvmovie.truecolor)
SKINNED=(FFNx FFNx.lighting FFNx.shadowmap)
n=0
FLAGS=(--platform osx --profile metal)
api=mtl
for s in "${SHADERS[@]}"; do
  for varying in flat smooth; do
    for stage in frag vert; do
      t=${stage:0:1}
      "$SHADERC" -i "$INC" -f "$SRC/$s.$stage" -o "$OUT/$s.$varying.$api.$stage" \
        --type "$t" --varyingdef "$SRC/FFNx.varying.$varying.def.sc" "${FLAGS[@]}"
      n=$((n + 1))
    done
  done
done
for s in "${SKINNED[@]}"; do
  "$SHADERC" -i "$INC" -f "$SRC/$s.vert" -o "$OUT/$s.skinned.smooth.$api.vert" \
    --type v --varyingdef "$SRC/FFNx.varying.smooth.def.sc" --define SMOOTH_SKINNING "${FLAGS[@]}"
  n=$((n + 1))
done
cp "$OUT"/*.$api.* "$ROOT/game/shaders/"
cp "$OUT"/*.$api.* "$ROOT/shaders/"
cp "$OUT"/*.$api.* "$CORE/game/shaders/"
echo "$n metal shaders -> game/shaders and ./shaders"
