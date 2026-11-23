#!/usr/bin/env bash
# Build the FF7 core (lifted game + runtime + FFNx + bgfx/Metal) for iOS and merge it into one
# static library the FF7RecompBundled app target links (ios/project.yml).
#
#   bash tools/build_ios_core.sh simulator   # -> build-ios-sim/libff7_bundle.a
#   bash tools/build_ios_core.sh device      # -> build-ios-device/libff7_bundle.a
#
# Needs the Android core set up and overlaid (tools/fetch_android_core.sh,
# tools/setup_android_core.sh, tools/apply_metal_overlay.sh) and a lift of your own ff7_en.exe
# under external/ff7-recomp-android/generated/recomp (docs/P1_METAL.md). The result contains that
# lift: it is for your own device only, never for distribution.
#
# Guest memory is based (FF7_BASED_MEMORY): iOS keeps a 4 GB PAGEZERO, so the flat layout of the
# Android and Rosetta builds is impossible there.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
KIND="${1:-simulator}"
case "$KIND" in
  simulator) SDK=iphonesimulator; B="$ROOT/build-ios-sim" ;;
  device)    SDK=iphoneos;        B="$ROOT/build-ios-device" ;;
  *) echo "usage: $0 simulator|device" >&2; exit 2 ;;
esac

cmake -S "$ROOT" -B "$B" \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$SDK" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DFF7_BUNDLE_GAME=ON -DFF7_PLATFORM=ios -DFF7_BUILD_TESTS=OFF -DFF7_BASED_MEMORY=ON >/dev/null
cmake --build "$B" -j "$(sysctl -n hw.ncpu)" --target ff7_guest ff7_core ffnx
FF7_LINK_MODE=bundle FF7_BUILD_DIR="$B" bash "$ROOT/tools/darwin_link_metal_boot.sh"
