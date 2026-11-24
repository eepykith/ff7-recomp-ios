# Building FF7Recomp iOS

## What works on this repo today

| Piece | Where | Runs on |
|---|---|---|
| Host C API smoke test | `tools/ff7_host_smoke.c` | Linux / macOS via CMake |
| Mac companion CLI | `tools/ff7recomp-mac` | Linux / macOS (Python 3) |
| SwiftUI launcher shell | `ios/FF7Recomp` | macOS + Xcode 15+ |

This page covers the pieces that build without the game. To build and run the game itself (Mac,
iOS simulator, iPhone), follow the README's "Using it" section; the details are in
[`P1_METAL.md`](P1_METAL.md).

## Linux / CI (engine stubs)

```bash
cmake -S . -B build -DFF7_PLATFORM=host
cmake --build build
ctest --test-dir build --output-on-failure
python3 tools/ff7recomp-mac --help
python3 -m unittest tests/test_validate.py
```

## Mac companion CLI

```bash
# An unsigned FF7Recomp.ipa with the game in it, to sign yourself (README, "On an iPhone").
python3 tools/ff7recomp-mac ipa

# Or build, sign and install on the connected iPhone in one go.
python3 tools/ff7recomp-mac install
python3 tools/ff7recomp-mac install --simulator booted     # or a simulator

# Check a Steam FF7 folder.
python3 tools/ff7recomp-mac validate "/path/to/FINAL FANTASY VII Steam Edition"
```

## iOS app (Mac + Xcode)

```bash
brew install xcodegen   # once
cd ios
xcodegen generate
open FF7Recomp.xcodeproj
```

Select an iPhone / iPad simulator or device, then Run.

Signing: use your personal team for sideload / development. App Store distribution
is out of scope (see `docs/IOS_PORT_PLAN.md`).

## The game (Mac and iOS)

See the README's "Using it" section and [`P1_METAL.md`](P1_METAL.md): set up the core, import
and lift your `ff7_en.exe`, then run `ff7_metal_boot` on the Mac or the `FF7RecompBundled` app
in the iOS simulator.
