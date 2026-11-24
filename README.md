# FF7Recomp iOS

A native iOS port of [FF7Recomp](https://github.com/bhuiyah/ff7-recomp-android): FINAL FANTASY VII
(Steam PC) statically recompiled to ARM64, rendered by FFNx through bgfx on Metal, with a launcher
for game setup and 7th Heaven mods. **No game files are included**: you build the game from your
own Steam copy.

iOS can't compile code on the device, so a Mac builds the game from your `ff7_en.exe` and installs
it on the iPhone; the iPhone gets the game files itself. Full plan: [`docs/IOS_PORT_PLAN.md`](docs/IOS_PORT_PLAN.md).

## Where it stands

**The FF7 title screen runs in the iOS app on the iOS simulator**, from the lifted game linked into
the app, drawn by FFNx → bgfx → Metal into the app's `CAMetalLayer`.

| Milestone | State |
|---|---|
| P0 toolchain, host ABI, launcher scaffold | Done |
| P1 Metal title screen | **Done on Mac and the iOS simulator**; device builds, not yet run |
| P2 playable slice (new game → Sector 7, controls, save states) | **In progress**: new game, first field, dialog and walking by touch |
| P3 setup (FF7Recomp Builder on the Mac makes the IPA) | Builder, kit and IPA pipeline work; game files built in or imported; not yet run on an iPhone |
| P4 mods | Mods screen done (import, enable, order); not applied in-game yet |
| P5–P6 launcher polish, catalogs, stretch goals | Not started |

What runs today:

| Target | Result |
|---|---|
| Mac, native arm64 (`ff7_metal_boot`) | New game → first field; movies, sound effects and music |
| Mac, Rosetta x86_64 (`ff7_metal_boot`) | New game → first field; movies, sound effects and music |
| iOS simulator (`FF7RecompBundled` app) | Launcher → Play → title → New Game → first field, played by touch |
| iPhone (`FF7RecompBundled` app) | Builds and links (unsigned); not yet run on hardware |
| Launcher shell (`FF7Recomp` app, no game) | Setup (game files), home, mods and settings screens |

Known gaps:

- **Movies need FFmpeg built first** (`tools/build_ffmpeg_apple.sh`, step 2b). Without it they
  end at once and the intro credits wait for Start. With it the Eidos logo and the opening movie
  play on the Mac (arm64 and Rosetta) and in the iOS simulator.
- **Sound on a real iPhone is untested.** Sound effects (the DirectSound mixer) go out through
  CoreAudio and music through FFNx's SoLoud/miniaudio engine; both are heard in the iOS simulator
  (`FF7_DSOUND_STATS=1` logs the mixer's buffers). The iOS audio session is miniaudio's default.
- **Dialog font spacing** needs `tools/fix_font_widths.py` run once on the game files (step 2);
  the iOS app's own import (P3) doesn't apply it yet.
- **Controllers** are wired (Apple's GameController framework) but untested with real hardware.
- **Device.** Running on an iPhone still needs a signing team, the game files on the device (P3
  import), and a check that iOS allows the game's 2 GB memory reservation (it may need the
  extended virtual addressing entitlement).

## How it works

- **The core** is the Android port's C/C++ engine: the lifted game, the Win32 shims, FFNx, and bgfx.
  It lives in `external/` (never committed), and this repo rebuilds it exactly: a pinned Android core,
  the Android port's own setup, then [`tools/apply_metal_overlay.sh`](tools/apply_metal_overlay.sh)
  (Metal, Apple fixes, and the `patches/*.patch` files).
- **Based guest memory.** The game's 32-bit memory lives in a 4 GB-aligned window at `g_mem_base`,
  because iOS (and native arm64 macOS) can't map anything below 4 GB.
  [`tools/based_memory_port.py`](tools/based_memory_port.py) converts the host code for this.
- **The iOS app** has two targets. `FF7Recomp` is the launcher alone. `FF7RecompBundled` links the
  whole core (your own lift, for your own devices only).

Details: [`docs/P1_METAL.md`](docs/P1_METAL.md).

## On an iPhone

iOS can't compile code on the phone, so **FF7Recomp Builder**, a small Mac app, builds the game
for you from your own FINAL FANTASY VII into an IPA, with your game files in it:

1. On a Mac with Xcode installed (it needs Xcode's iOS SDK and compiler), open FF7Recomp Builder.
   It finds your Steam install of the game (or choose the `FINAL FANTASY VII Steam Edition`
   folder, the one with `ff7` inside) and checks `ff7_en` is the 1.02 US build. No patch or older
   version is needed; patched game files are not supported.
2. Build FF7Recomp.ipa. The builder lifts `ff7_en` to C, compiles it for iPhone, links it with the
   engine it carries, and puts your `ff7_en.exe` and `data/` (English, French, German, Spanish,
   with the dialog font fix) in the app. The first build takes a while; the IPA is about 3 GB.
3. Sign the IPA and install it on your iPhone (a development profile, AltStore, SideStore...).
   Keep the extended virtual addressing entitlement if your profile has it: the game reserves
   4 GB of address space.
4. Open FF7Recomp: it confirms your game files, and Play starts the game. Mods unlock once the
   game files are confirmed.

The builder holds no game code and no game files (its engine is built without the game,
`FF7_NO_GUEST`), so it can be shared. **The IPA it makes holds the game built from your copy and
your game's files: for your own devices only, never share it.**

To make the builder: set up the core (steps 1 and 2b below), then

```bash
bash tools/make_builder_kit.sh                 # the engine kit -> build-builder/kit
cd mac/builder && xcodegen generate && xcodebuild -scheme FF7RecompBuilder -configuration Release \
  -derivedDataPath ../../build-builder/dd build  # -> build-builder/dd/Build/Products/Release/FF7Recomp Builder.app
```

Without the Mac app, `python3 mac/builder/build_ipa.py --kit build-builder/kit --game "<FF7 folder>"
--out FF7Recomp.ipa` does the same build. For development there are also `tools/ff7recomp-mac
ipa` (an IPA without game files, which asks for them on the phone: Find my FF7 folder) and
`tools/ff7recomp-mac install` (builds, signs and installs over a cable).

## Using it

You need a Mac with Apple silicon, Xcode, your Steam copy of FINAL FANTASY VII (the 2026 Steam
Edition layout), and:

```bash
brew install cmake llvm xcodegen
```

### 1. Set up the core

```bash
bash tools/fetch_android_core.sh     # Android core, pinned
bash tools/setup_android_core.sh     # its dependencies and FFNx transforms
bash tools/apply_metal_overlay.sh    # Metal, based memory, Apple patches
```

### 2. Import and lift your game

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

Then make the `game/` folder the engine runs from (gitignored), with the Metal shaders and FFNx's
settings:

```bash
mkdir -p game
ln -sfn "$PWD/$AND/game/data" game/data
ln -sfn "$PWD/$AND/game/ff7_en.exe" game/ff7_en.exe
cp "$AND/external/FFNx/misc/FFNx.toml" game/FFNx.toml
make -C "$AND/external/bgfx" shaderc
bash tools/compile_shaders_metal.sh  # writes game/shaders
python3 -I tools/fix_font_widths.py game   # dialog font widths (M/W/m/w) in the 2026 files
```

`fix_font_widths.py` patches `data/lang-{en,fr,de,es}/kernel/window.bin` in place, as the Android
installer does: the 2026 Steam files give M, W, m and w 8 pixels where the font draws them 11 wide,
so dialog runs them into the next letter ("C'mon newcom≡r"). It is idempotent; `--check` only
reports.

### 2b. Build FFmpeg (movies)

```bash
bash tools/build_ffmpeg_apple.sh macos-arm64     # also: macos-x86_64, ios-simulator, ios-device
```

This builds FFmpeg n9.0.2 (FFNx's version) as static libraries for that target, decoding the
movies' VP8 and Vorbis in software. Build the FFmpeg target before configuring (or re-run
`cmake` on) the matching build folder; without it, FFNx uses movie stubs.

### 3a. Run on the Mac

```bash
cmake -S . -B build-metal-arm64 -DFF7_BUNDLE_GAME=ON -DFF7_PLATFORM=mac \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DFF7_BUILD_TESTS=OFF -DFF7_BASED_MEMORY=ON
cmake --build build-metal-arm64 -j --target ffnx ff7_core ff7_platform
FF7_BUILD_DIR=$PWD/build-metal-arm64 bash tools/darwin_link_metal_boot.sh
FF7_QUICKBOOT=title ./build-metal-arm64/ff7_metal_boot game
```

### 3b. Run in the iOS simulator

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

Tap **Play**. The play view turns landscape and shows the game at 4:3, as large as the screen
allows, with an on-screen pad (d-pad, A/B/X/Y, L1/R1, Select/Start); a game controller works too.
B is OK, A is cancel, ✕ quits to the launcher. On an iPhone the pad sits in the bars beside the
picture; on screens near 4:3 (iPhone Duo, iPad) it lies over the picture's edges. The picture
follows the screen when it changes size (iPhone Duo folding and unfolding, split screen). While
the iPhone Duo's hinge is open or half open (SwiftUI's hinge status, iOS 27.1) the play view also
turns upright: the picture sits in the top half and the bottom half is the Android port's
bottom-screen panel, clear of the fold. Its centre column shows where the party is, play time,
gil, and each member's HP, MP and Limit (ATB and the enemies' HP in battle), with touch buttons
for Menu, save and load state, speed 1×/2×/3×, random battles on/off and Battle+. The pad keeps
to the side columns, so a thumb on it never hits those buttons; with a game controller connected
the pad is hidden (`FF7_TOUCHPAD=1` keeps it). Shut, the Duo goes back to landscape on the outer
screen. An iPad turns upright the same way.
`FF7_QUICKBOOT=title` (or `newgame`) skips ahead; leave it out to play from the intro. The
engine's log prints in the terminal.

For an iPhone, `bash tools/build_ios_core.sh device` builds the core, and the `FF7RecompBundled`
scheme builds for `iphoneos`. Running it needs the steps under "Known gaps".

### Launcher only (no game)

```bash
cd ios && xcodegen generate && open FF7Recomp.xcodeproj   # scheme FF7Recomp; Cmd-U runs the tests
```

## Layout

```
ios/              SwiftUI app (XcodeGen spec): launcher, setup, mods, play view
src/platform/     Shared C host API (ff7_host_*, ff7_platform_*)
src/ios/          Metal view, 64 MB game thread
src/mac/          Mac Metal window + Rosetta guest reservation
src/ffnx_overlay/ Sources added to FFNx on Apple (renderer selectors, movie stubs)
mac/builder/      FF7Recomp Builder (Mac app) and build_ipa.py, its IPA pipeline
mac/ff7recomp_mac ff7recomp-mac developer CLI (install, ipa)
tools/            Setup, overlay, based-memory port, build and link scripts
patches/          Apple patches applied on top of the Android core
docs/             Port plan, build notes, P1 details
```

## Legal

You need your own Steam copy of FINAL FANTASY VII. Builds that include the lifted game are for your
own devices only and must not be distributed. Not affiliated with or endorsed by Square Enix.
FINAL FANTASY is a trademark of Square Enix. Sideload / developer distribution only, not the App
Store.
