#!/bin/sh
# Clone ff7-recomp-android into external/ for the Metal link, at the commit the Darwin
# patches (patches/*-darwin.patch, tools/apply_metal_overlay.sh) were made against.
# The tree is gitignored. It contains no game files.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DEST="$ROOT/external/ff7-recomp-android"
REV=7218386974c89ebb20cb6b0ebd4b58c3a8a2ca0b
if [ ! -d "$DEST/.git" ]; then
  git init -q "$DEST"
  git -C "$DEST" remote add origin https://github.com/bhuiyah/ff7-recomp-android.git
fi
if [ "$(git -C "$DEST" rev-parse -q --verify HEAD || true)" != "$REV" ]; then
  git -C "$DEST" fetch -q --depth 1 origin "$REV"
  git -C "$DEST" checkout -q "$REV"
fi
echo "Android core: $DEST @ $(git -C "$DEST" rev-parse --short HEAD)"
echo "Next: bash tools/setup_android_core.sh && bash tools/apply_metal_overlay.sh"
