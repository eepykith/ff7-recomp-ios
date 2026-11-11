# FF7Recomp iOS

Native iOS host (in progress) for
[FF7Recomp on Android](https://github.com/bhuiyah/ff7-recomp-android):
FINAL FANTASY VII (Steam PC) statically recompiled to ARM64, rendered by FFNx,
with a 7th Heaven–style mod launcher. **No game files are included.**

## Status: P0 scaffold

| Done | Not yet |
|---|---|
| SwiftUI launcher shell | FFNx / Metal title screen (P1) |
| C host API + smoke test | Real pcrecomp lift → arm64-ios |
| `ff7recomp-mac` validate / stub `.ff7pkg` | Signed game dylib package (P3) |
| XcodeGen project | Mods, save states, catalogs |

Plan: [`docs/IOS_PORT_PLAN.md`](docs/IOS_PORT_PLAN.md)  
Build: [`docs/BUILDING.md`](docs/BUILDING.md)

## Quick start

```bash
# Engine stub (Linux or Mac)
cmake -S . -B build && cmake --build build && ctest --test-dir build --output-on-failure

# Companion CLI
python3 tools/ff7recomp-mac validate "/path/to/FINAL FANTASY VII"
python3 tools/ff7recomp-mac build-package "/path/to/FINAL FANTASY VII" -o GamePackage.ff7pkg

# iOS app (Mac)
cd ios && xcodegen generate && open FF7Recomp.xcodeproj
```

## Layout

```
ios/           SwiftUI app + XcodeGen spec
mac/           ff7recomp-mac companion (Python)
src/platform/  Shared C host API
src/ios/       Metal window stubs (P1)
cmake/         iOS toolchain file
docs/          Port plan + build notes
tools/         CLI entry + C smoke test
```

## Legal

You need your own Steam copy of FINAL FANTASY VII. Not affiliated with or
endorsed by Square Enix. FINAL FANTASY is a trademark of Square Enix.
Sideload / developer distribution only — not App Store.
