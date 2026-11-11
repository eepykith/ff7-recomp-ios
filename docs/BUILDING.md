# Building FF7Recomp iOS (P0 scaffold)

## What works on this repo today

| Piece | Where | Runs on |
|---|---|---|
| Host C API smoke test | `tools/ff7_host_smoke.c` | Linux / macOS via CMake |
| Mac companion CLI | `tools/ff7recomp-mac` | Linux / macOS (Python 3) |
| SwiftUI launcher shell | `ios/FF7Recomp` | macOS + Xcode 15+ |

P1 presents a `CAMetalLayer` and the Android-compatible `ff7_platform_window()`
ABI. FFNx is not linked yet, so the layer clears to a status color instead of
drawing the game. See [`P1_METAL.md`](P1_METAL.md).

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
# Point at your Steam FF7 folder (must contain ff7_en.exe).
python3 tools/ff7recomp-mac validate "/path/to/FINAL FANTASY VII"

# Write a stub .ff7pkg (manifest + exe fingerprint only — no game bytes).
python3 tools/ff7recomp-mac build-package "/path/to/FINAL FANTASY VII" -o GamePackage.ff7pkg
```

Import the `.ff7pkg` in the iOS app under **Game → Import GamePackage…**.

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

## Next (rest of P1)

1. `bash tools/fetch_android_core.sh`
2. Build FFNx/bgfx for Metal and call `ff7_boot_and_run` on a 64 MB game thread.
3. Enable `FF7_BUNDLE_GAME` only for a local lift of your own `ff7_en.exe`.
