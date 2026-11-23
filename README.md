# FF7Recomp iOS

A native iOS port of [FF7Recomp](https://github.com/bhuiyah/ff7-recomp-android): FINAL FANTASY VII
(Steam PC) statically recompiled to ARM64, rendered by FFNx through bgfx on Metal, with a launcher
for game setup and 7th Heaven mods. **No game files are included**: you build the game from your
own Steam copy.

iOS can't compile code on the device, so the plan is: a Mac companion recompiles your
`ff7_en.exe`, and the iPhone imports the result. Full plan: [`docs/IOS_PORT_PLAN.md`](docs/IOS_PORT_PLAN.md).

## Where it stands

**The FF7 title screen runs in the iOS app on the iOS simulator**, from the lifted game linked into
the app, drawn by FFNx → bgfx → Metal into the app's `CAMetalLayer`.

| Milestone | State |
|---|---|
| P0 toolchain, host ABI, launcher scaffold | Done |
| P1 Metal title screen | **Done on Mac and the iOS simulator**; device builds, not yet run |
| P2 playable slice (new game → Sector 7, controls, save states) | Next |
| P3 GamePackage workflow (Mac builds, iPhone imports) | Launcher screens done; package loading not yet |
| P4 mods | Mods screen done (import, enable, order); not applied in-game yet |
| P5–P6 launcher polish, catalogs, stretch goals | Not started |

What runs today:

| Target | Result |
|---|---|
| Mac, native arm64 (`ff7_metal_boot`) | Title screen |
| Mac, Rosetta x86_64 (`ff7_metal_boot`) | Title screen |
| iOS simulator (`FF7RecompBundled` app) | Launcher → Play → title screen |
| iPhone (`FF7RecompBundled` app) | Builds and links (unsigned); not yet run on hardware |
| Launcher shell (`FF7Recomp` app, no game) | Setup, home, mods and settings screens; 23 unit tests pass |

Known gaps:

- **No movies.** FFmpeg isn't built for Apple platforms yet, so movies end at once, and the intro
  credits don't advance on their own. Use `FF7_QUICKBOOT=title` to go straight to the title.
- **Play view layout.** The 4:3 image is stretched to the screen, and it keeps its boot size when
  the device rotates.
- **No Start button** on the touch pad yet, and sound is a silent stub on Apple platforms.
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
```

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
cd ios && xcodegen generate
xcodebuild -scheme FF7RecompBundled -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath ../build-ios-dd build
xcrun simctl install booted ../build-ios-dd/Build/Products/Debug-iphonesimulator/FF7RecompBundled.app
bash ../tools/ios_sim_link_game.sh              # app's Documents/game -> ../game
SIMCTL_CHILD_FF7_QUICKBOOT=title xcrun simctl launch --console-pty booted com.ff7recomp.ios.bundled
```

Tap **Play** to reach the title screen. The engine's log prints in the terminal.

For an iPhone, `bash tools/build_ios_core.sh device` builds the core, and the `FF7RecompBundled`
scheme builds for `iphoneos`. Running it needs the steps under "Known gaps".

### Launcher only (no game)

```bash
cd ios && xcodegen generate && open FF7Recomp.xcodeproj   # scheme FF7Recomp; Cmd-U runs the tests
```

### Mac companion CLI

```bash
python3 tools/ff7recomp-mac validate "/path/to/FINAL FANTASY VII"
python3 tools/ff7recomp-mac build-package "/path/to/FINAL FANTASY VII" -o GamePackage.ff7pkg
```

Today this writes a manifest-only `.ff7pkg` (exe fingerprint, no game code) that the launcher can
import and verify. Building the real package with the compiled game is P3.

## Layout

```
ios/              SwiftUI app (XcodeGen spec): launcher, setup, mods, play view
src/platform/     Shared C host API (ff7_host_*, ff7_platform_*)
src/ios/          Metal view, 64 MB game thread
src/mac/          Mac Metal window + Rosetta guest reservation
src/ffnx_overlay/ Sources added to FFNx on Apple (renderer selectors, movie stubs)
mac/              ff7recomp-mac companion (Python)
tools/            Setup, overlay, based-memory port, build and link scripts
patches/          Apple patches applied on top of the Android core
docs/             Port plan, build notes, P1 details
```

## Legal

You need your own Steam copy of FINAL FANTASY VII. Builds that include the lifted game are for your
own devices only and must not be distributed. Not affiliated with or endorsed by Square Enix.
FINAL FANTASY is a trademark of Square Enix. Sideload / developer distribution only, not the App
Store.
