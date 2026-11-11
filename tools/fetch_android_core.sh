#!/bin/sh
# Clone ff7-recomp-android into external/ for the P1 FFNx link.
# The tree is gitignored. It contains no game files.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DEST="$ROOT/external/ff7-recomp-android"
if [ ! -d "$DEST/.git" ]; then
  git clone --depth 1 https://github.com/bhuiyah/ff7-recomp-android.git "$DEST"
else
  git -C "$DEST" pull --ff-only
fi
echo "Android core: $DEST"
echo "Not built yet. FFNx/Metal link is the next step after a local lift of your ff7_en.exe."
