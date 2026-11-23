#!/usr/bin/env bash
# Mac/Unix mirror of external/ff7-recomp-android/tools/setup.ps1 + fetch_deps.sh.
# Requires: bash tools/fetch_android_core.sh first. Tree stays under external/ (gitignored).
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
AND="$ROOT/external/ff7-recomp-android"
EXT="$AND/external"

if [ ! -d "$AND/.git" ]; then
  echo "missing Android core — run: bash tools/fetch_android_core.sh" >&2
  exit 1
fi

pin_repo() {
  local name=$1 url=$2 rev=$3 patch_dir=${4:-}
  local dir="$EXT/$name"
  if [ ! -d "$dir/.git" ]; then
    git clone -q "$url" "$dir"
  fi
  git -C "$dir" fetch -q origin
  git -C "$dir" reset -q --hard
  git -C "$dir" clean -qfd
  git -C "$dir" checkout -q "$rev"
  if [ -n "$patch_dir" ] && [ -d "$AND/$patch_dir" ]; then
    local p
    for p in "$AND/$patch_dir"/*.patch; do
      [ -f "$p" ] || continue
      # FFNx sources are CRLF; ignore-whitespace keeps git-apply happy on macOS.
      git -C "$dir" apply --ignore-whitespace "$p"
      echo "  applied $name/$(basename "$p")"
    done
  fi
  echo "$name @ $(git -C "$dir" rev-parse --short HEAD)"
}

mkdir -p "$EXT"
pin_repo pcrecomp https://github.com/sp00nznet/pcrecomp.git 35548b8d0fd8aa853da67edcf7cd6134f6b9cdc7 patches/pcrecomp
pin_repo FFNx https://github.com/julianxhokaxhiu/FFNx.git 0adf0b32 patches/ffnx
pin_repo nfsu2-recompiled https://github.com/codepdbh/nfsu2-recompiled.git main
pin_repo bx https://github.com/julianxhokaxhiu/bx.git c99974204c15405b69647d5097af1102e6210c91
pin_repo bimg https://github.com/julianxhokaxhiu/bimg.git 671fe06dd7012a1ab85aa931019ed16112909756
pin_repo bgfx https://github.com/julianxhokaxhiu/bgfx.git 1f93b90898dcc492587b617b397e2d2285dcd0ec patches/bgfx

python3 -I "$AND/tools/ffnx_port.py" gptr
python3 -I "$AND/tools/ffnx_port.py" casts
python3 -I "$AND/tools/ffnx_port.py" calls
python3 -I "$AND/tools/ffnx_port.py" overrides
python3 -I "$AND/tools/ffnx_edit_android.py"
bash "$AND/tools/fetch_deps.sh"
echo "Android toolkits ready under $EXT"
