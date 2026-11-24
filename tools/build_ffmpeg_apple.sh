#!/usr/bin/env bash
# Build FFmpeg n9.0.2 (the version FFNx pins) as static libraries for Apple targets, for FFNx's
# movie player. Same feature set as the Android core's tools/build_ffmpeg_android.sh: the 2026
# release's movies are Matroska with VP8 video and Vorbis audio (data/movies/*.avi), which FFmpeg
# decodes in software. VideoToolbox does not decode VP8, and FFNx's player does not set up a
# hardware decoder, so it is left out (as are the other autodetected system libraries, except zlib).
#
#   bash tools/build_ffmpeg_apple.sh macos-arm64      # native Mac runner (build-metal-arm64)
#   bash tools/build_ffmpeg_apple.sh macos-x86_64     # Rosetta Mac runner (build-metal-x64)
#   bash tools/build_ffmpeg_apple.sh ios-simulator    # build-ios-sim (arm64 simulator)
#   bash tools/build_ffmpeg_apple.sh ios-device       # build-ios-device
#
# Output: external/ff7-recomp-android/build/ffmpeg-apple-<target>/{include,lib}, where the
# overlaid cmake/ffnx.cmake finds it (FF7_IOS_FFMPEG_APPLE in tools/apply_metal_overlay.sh).
# Re-run cmake for that build tree afterwards: FFNx then builds its real movie player instead
# of src/ffnx_overlay/ffmpeg_movie_stubs.cpp.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
AND="$ROOT/external/ff7-recomp-android"
SRC="$AND/external/deps/ffmpeg"
TARGET="${1:-}"
case "$TARGET" in
  macos-arm64)   SDK=macosx;          ARCH=aarch64; TRIPLE=arm64-apple-macos11.0 ;;
  macos-x86_64)  SDK=macosx;          ARCH=x86_64;  TRIPLE=x86_64-apple-macos11.0 ;;
  ios-simulator) SDK=iphonesimulator; ARCH=aarch64; TRIPLE=arm64-apple-ios17.0-simulator ;;
  ios-device)    SDK=iphoneos;        ARCH=aarch64; TRIPLE=arm64-apple-ios17.0 ;;
  *) echo "usage: $0 macos-arm64|macos-x86_64|ios-simulator|ios-device" >&2; exit 2 ;;
esac
OUT="$AND/build/ffmpeg-apple-$TARGET"
[ -d "$AND/cmake" ] || { echo "missing $AND: run tools/fetch_android_core.sh first" >&2; exit 1; }

if [ ! -f "$SRC/configure" ]; then
  git -c advice.detachedHead=false clone -q --depth 1 -b n9.0.2 https://github.com/FFmpeg/FFmpeg.git "$SRC"
fi

SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
CC="$(xcrun --sdk "$SDK" -f clang)"
FLAGS="-target $TRIPLE -isysroot $SYSROOT -O2 -fPIC -ffile-prefix-map=$SRC=ffmpeg"
EXTRA=()
# x86 assembly needs nasm; the Rosetta runner only plays movies, so plain C is enough there.
[ "$ARCH" = x86_64 ] && EXTRA+=(--disable-x86asm)
[ "$ARCH" = aarch64 ] && EXTRA+=(--enable-neon)
# Cross builds (iOS, or x86_64 on an arm64 Mac) cannot run the test programs configure builds.
if [ "$SDK" != macosx ] || [ "$(uname -m)" != "${ARCH/aarch64/arm64}" ]; then
  EXTRA+=(--enable-cross-compile)
fi

rm -rf "$OUT"
mkdir -p "$OUT/build"
cd "$OUT/build"
"$SRC/configure" \
  --prefix="$OUT" \
  --target-os=darwin --arch="$ARCH" \
  --cc="$CC" --ar="$(xcrun --sdk "$SDK" -f ar)" --ranlib="$(xcrun --sdk "$SDK" -f ranlib)" \
  --nm="$(xcrun --sdk "$SDK" -f nm)" --strip="$(xcrun --sdk "$SDK" -f strip)" \
  --host-cc=/usr/bin/clang \
  --extra-cflags="$FLAGS" --extra-ldflags="-target $TRIPLE -isysroot $SYSROOT" \
  --pkg-config=false \
  --enable-static --disable-shared --enable-pic \
  --disable-programs --disable-doc --disable-debug --disable-avdevice --disable-avfilter \
  --disable-autodetect --enable-zlib \
  --disable-everything \
  --enable-avcodec --enable-avformat --enable-avutil --enable-swscale --enable-swresample \
  --enable-protocol=file \
  --enable-demuxer=matroska,ogg,avi,mov,mp3,wav \
  --enable-decoder=vp8,vp9,vorbis,opus,h264,mpeg4,aac,mp3,pcm_s16le,adpcm_ms \
  --enable-parser=vp8,vp9,vorbis,opus,h264,mpeg4video,aac,mpegaudio \
  "${EXTRA[@]}" > "$OUT/configure.log" 2>&1 || { tail -30 "$OUT/configure.log"; exit 1; }
# FFmpeg compiles its configure line into the libraries (avcodec_configuration()): it names this
# Mac's folders. A neutral line instead.
sed -i '' 's|^#define FFMPEG_CONFIGURATION .*|#define FFMPEG_CONFIGURATION "FF7Recomp tools/build_ffmpeg_apple.sh"|' config.h
echo "configured $TARGET; building"
make -j"$(sysctl -n hw.ncpu)" > "$OUT/make.log" 2>&1 || { tail -30 "$OUT/make.log"; exit 1; }
make install > "$OUT/install.log" 2>&1 || { tail -30 "$OUT/install.log"; exit 1; }
rm -rf "$OUT/build" "$OUT/share" "$OUT/lib/pkgconfig"
ls -la "$OUT/lib"
