# Building FF7Recomp for iOS from source

For players, the [release](https://github.com/eepykith/ff7-recomp-ios/releases) has FF7Recomp
Builder ready to use (see the README). This page is for working on FF7Recomp itself: setting up
the core, running the game on the Mac and in the iOS simulator, and making the builder.

You need a Mac with Apple silicon, Xcode, your Steam copy of FINAL FANTASY VII (the Steam Edition
layout, as Steam installs it today), and:

```bash
brew install cmake llvm xcodegen
python3 -m pip install --user capstone pefile    # the lifter's modules
```

## 1. Set up the core

The engine is the Android port's C/C++ core (the lifter's runtime, the Win32 shims, FFNx, bgfx).
It lives in `external/` (never committed); these scripts fetch a pinned copy and put the Apple
layer on top:

```bash
bash tools/fetch_android_core.sh     # Android core, pinned
bash tools/setup_android_core.sh     # its dependencies and FFNx transforms
bash tools/apply_metal_overlay.sh    # Metal, based memory, Apple patches (idempotent)
```

## 2. Import and lift your game

```bash
AND=external/ff7-recomp-android
STEAM="$HOME/Library/Application Support/Steam/steamapps/common/FINAL FANTASY VII Steam Edition"
python3 -I "$AND/tools/import_game.py" "$STEAM"

mkdir -p "$AND/analysis"
gunzip -c "$AND/config/catalog.json.gz" > "$AND/analysis/catalog.json"
python3 -I "$AND/tools/run_lift.py" lift "$AND/game/ff7_en.exe" \
  "$AND/analysis/catalog.json" "$AND/generated/recomp"
python3 -I "$AND/tools/gen_extents.py" "$AND/generated/recomp"
python3 -I "$AND/tools/gen_retn_table.py"
```

Then make the `game/` folder the Mac and simulator builds run from (gitignored), with the Metal
shaders and FFNx's settings:

```bash
mkdir -p game
ln -sfn "$PWD/$AND/game/data" game/data
ln -sfn "$PWD/$AND/game/ff7_en.exe" game/ff7_en.exe
cp "$AND/external/FFNx/misc/FFNx.toml" game/FFNx.toml
make -C "$AND/external/bgfx" shaderc
bash tools/compile_shaders_metal.sh          # writes game/shaders
python3 -I tools/fix_font_widths.py game     # dialog font widths in the current Steam files
```

`fix_font_widths.py` patches `data/lang-{en,fr,de,es}/kernel/window.bin` in place, as the Android
installer does: the current Steam files give M, W, m and w 8 pixels where the font draws them 11
wide, so dialog runs them into the next letter. It is idempotent; `--check` only reports.
FF7Recomp Builder and the app's folder import apply it themselves.

## 3. Build FFmpeg (movies)

```bash
bash tools/build_ffmpeg_apple.sh macos-arm64     # also: ios-simulator, ios-device, macos-x86_64
```

FFmpeg n9.0.2 (FFNx's version) as static libraries for that target. Build it before configuring
the matching build folder; without it FFNx uses movie stubs and movies end at once.

## 4. Run on the Mac

The quickest way to debug the engine:

```bash
cmake -S . -B build-metal-arm64 -DFF7_BUNDLE_GAME=ON -DFF7_PLATFORM=mac \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DFF7_BASED_MEMORY=ON
cmake --build build-metal-arm64 -j --target ffnx ff7_core ff7_platform
FF7_BUILD_DIR=$PWD/build-metal-arm64 bash tools/darwin_link_metal_boot.sh
FF7_QUICKBOOT=title ./build-metal-arm64/ff7_metal_boot game
```

`FF7_QUICKBOOT=title` (or `newgame`) skips ahead; leave it out to play from the intro.

## 5. Run in the iOS simulator

```bash
bash tools/build_ios_core.sh simulator          # -> build-ios-sim/libff7_bundle.a
bash tools/stage_ffnx_runtime.sh                # FFNx's shaders and settings for the app
cd ios && xcodegen generate
xcodebuild -scheme FF7RecompBundled -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath ../build-ios-dd build
xcrun simctl install booted ../build-ios-dd/Build/Products/Debug-iphonesimulator/FF7RecompBundled.app
bash ../tools/ios_sim_link_game.sh              # the app's game folder -> ../game
SIMCTL_CHILD_FF7_QUICKBOOT=title xcrun simctl launch --console-pty booted com.ff7recomp.ios
```

The engine's log prints in the terminal. Useful environment variables (`SIMCTL_CHILD_` on the
simulator): `FF7_QUICKBOOT=title|newgame`, `FF7_TOUCHPAD=1` (show the touch pad even with a
controller connected), `FF7_DSOUND_STATS=1` (sound mixer statistics).

The `FF7Recomp` scheme is the launcher alone, without the game; its unit tests run with Cmd-U in
Xcode (`ios/FF7Recomp.xcodeproj`).

## 6. Make FF7Recomp Builder

```bash
bash tools/build_ffmpeg_apple.sh ios-device
bash tools/make_builder_kit.sh                  # the engine kit -> build-builder/kit
bash tools/package_builder.sh 0.2.3b            # -> build-builder/release/FF7Recomp-Builder-0.2.3b.zip
```

The kit is everything the iOS app needs except the game: the engine built without the lift
(`FF7_NO_GUEST`), the app's compiled code and its link line, the app's resources, and the lifter.
Both scripts refuse to finish if the kit holds lifted game code, game files or paths of the
build Mac, so the builder can be shared.

[`mac/builder/build_ipa.py`](../mac/builder/build_ipa.py) is the builder's whole pipeline and
runs on its own too:

```bash
python3 mac/builder/build_ipa.py --kit build-builder/kit \
  --game "<FINAL FANTASY VII Steam Edition folder>" --out FF7Recomp.ipa
```

## How it fits together

- **Based guest memory.** The game's 32-bit memory lives in a 4 GB-aligned window at
  `g_mem_base`, because iOS (and native arm64 macOS) can't map anything below 4 GB.
  [`tools/based_memory_port.py`](../tools/based_memory_port.py) converts the host code for this.
- **Rendering.** FFNx draws through bgfx's Metal backend into the app's `CAMetalLayer`
  ([`src/ios/FF7MetalView.mm`](../src/ios/FF7MetalView.mm)); a change of surface size (rotation,
  folding) resets FFNx's swap chain.
- **The app** (`ios/`, an XcodeGen spec) has two targets: `FF7Recomp` is the launcher alone,
  `FF7RecompBundled` links the whole core. Both have the bundle ID `com.ff7recomp.ios`.
- More engine notes: [`P1_METAL.md`](P1_METAL.md).

## Layout

```
ios/              SwiftUI app: launcher, setup, mods, play view, touch pad, status panel
src/platform/     Shared C host API (ff7_host_*, ff7_platform_*)
src/ios/          Metal view, game thread, status panel bridge
src/ios_mods/     Unpacking mod downloads (zip; 7z with the Android core's un7z.c)
src/mac/          Mac Metal window (the Mac runner)
src/ffnx_overlay/ Sources added to FFNx on Apple
src/hle_overlay/  Apple replacements in the game's HLE layer (CoreAudio sound)
mac/builder/      FF7Recomp Builder (Mac app) and build_ipa.py
tools/            Setup, overlay, build, kit, packaging and icon scripts
patches/          Apple patches applied on top of the Android core
cmake/            CMake glue for the Android core on Apple
docs/             Build notes, engine notes, release notes, screenshots
```
