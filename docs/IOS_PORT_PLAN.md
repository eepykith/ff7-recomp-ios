# FF7Recomp for iOS — Port Plan

Plan for an iOS counterpart to
[bhuiyah/ff7-recomp-android](https://github.com/bhuiyah/ff7-recomp-android):
FINAL FANTASY VII (Steam PC) statically recompiled to native ARM64, rendered by
FFNx, with a 7th Heaven–style mod launcher. No game files are ever redistributed.

> Not affiliated with or endorsed by Square Enix. FINAL FANTASY is a trademark of
> Square Enix. This plan assumes the same legal model as Android: the user
> supplies their own Steam copy; the app never ships derived game code.

---

## 1. Verdict

An iOS port is **technically feasible as a sideloaded / developer-distributed
native app**, but it is **not a straight port of the Android APK**. The Android
app’s defining trick — *on-device clang that compiles the user’s `ff7_en.exe`
into a loadable shared library* — collides with iOS codesigning and W^X.

| Path | Feasible? | Notes |
|---|---|---|
| App Store IPA with on-device recomp | No | Unsigned/generated executable pages are forbidden; App Review will reject game recomp + GPL tooling |
| Sideloaded IPA (AltStore / SideStore / TrollStore / Dev cert) with **Mac-side** recomp | Yes | Closest to Android UX: user owns the game, build happens once |
| Sideloaded IPA with embedded **x86 interpreter** only (no native lift) | Partial | Works for proof-of-concept; too slow for 60 FPS target |
| Mac Catalyst / native Mac first, then iOS | Yes (recommended bootstrap) | Same Metal + codesign story, easier debugging |

**Recommended strategy:** treat iOS as a second host for the existing C/C++
core, replace Android Java with SwiftUI, switch bgfx to **Metal**, and move the
one-time recompile off the phone onto a **Mac companion CLI** (or a Mac build
step that stamps a signed game binary into the app container for sideload).

---

## 2. What the Android app actually is

Understanding the layers is the whole port.

```
┌─────────────────────────────────────────────────────────────┐
│  Launcher (Java)                                            │
│  Game files · Mods · Settings · Save states · Achievements  │
├─────────────────────────────────────────────────────────────┤
│  BuildService  →  on-device kit (clang, lld, Python, lifter) │
│  lifts ff7_en.exe → C → links libff7.so with engine         │
├─────────────────────────────────────────────────────────────┤
│  Game runtime (C/C++)                                       │
│  pcrecomp guest  │  Win32 HLE  │  mods (IRO/hext)  │  host  │
├─────────────────────────────────────────────────────────────┤
│  FFNx port (gptr/gfn bridge)  →  bgfx (Vulkan / GLES)       │
└─────────────────────────────────────────────────────────────┘
```

| Layer | Location in Android repo | Portability to iOS |
|---|---|---|
| Lifter / catalog / manifests | `tools/run_lift.py`, `config/` | **Reuse as-is** (Mac host) |
| Guest runtime + HLE | `src/host`, `src/hle`, `src/interp` | **Mostly reuse**; path/audio/window shims |
| Mod system | `src/mods` | **Reuse** (IRO, mod.xml, hext, union FS) |
| FFNx bridge | `src/ffnx_bridge`, `src/ffnx_port` | **Port**; replace Android window/input/Steam |
| Renderer | bgfx Vulkan/GLES | **Switch to Metal** (`BGFX_CONFIG_RENDERER_METAL`) |
| Launcher UI | `android/app/.../java/com/ff7recomp/*` | **Rewrite** in SwiftUI |
| On-device build kit | `android/kit`, `tools/build_device_*` | **Replace** with Mac companion + signed package |
| Dual-screen companion | `CompanionView.java`, `companion*.cpp` | **Defer**; iPad external display later |

---

## 3. The hard blocker: codesigning vs on-device build

Android loads `libff7.so` after the device compiles it. On iOS:

1. Every executable page must be covered by a valid code signature.
2. Apps cannot JIT or `mprotect` RWX (W^X).
3. `dlopen` of an unsigned / ad-hoc unsigned dylib built at runtime fails on
   non-jailbroken devices.
4. Shipping a full LLVM/clang toolchain inside an App Store binary is both
   enormous and review-hostile.

### Chosen model: Mac-side recomp → signed game blob → iOS host

```
User's Steam FF7 folder
        │
        ▼
┌───────────────────────┐
│  ff7recomp-mac CLI    │  (runs on Mac / CI Mac)
│  1. Validate files    │
│  2. Lift with pcrecomp│
│  3. clang → arm64-ios │
│  4. Link engine stubs │
│  5. codesign dylib    │
└───────────┬───────────┘
            │  GamePackage.zip
            │  (libff7.dylib + data layout + hash)
            ▼
┌───────────────────────┐
│  FF7Recomp iOS app    │  (sideloaded IPA)
│  Import package       │
│  Verify signature/hash│
│  Launch Metal surface │
└───────────────────────┘
```

**Jailbroken / TrollStore optional path:** keep an on-device clang kit closer to
Android. Treat as a stretch goal, not the primary design.

**Fallback for development:** `FF7_BUNDLE_GAME` equivalent — lift on Mac and
link the game into the IPA at Xcode build time (Android already has this flag).

---

## 4. Target product (MVP)

### In scope for v0.1

- Sideloaded IPA for **iPhone + iPad** (iOS 17+, arm64 only)
- Import a **Mac-built GamePackage** (or Xcode-bundled game for testers)
- Play native ARM64 FF7 via FFNx on **Metal**, 30/60 FPS
- Controller via **GameController**; on-screen touch pad when none is present
- Widescreen 16:9 / stretch option; CRT filter if portable cheaply
- Save states (reuse `ff7_savestate.c` format)
- Local RetroAchievements set (offline), no Steam QR yet
- Mod library: enable/order imported `.iro` / folders (catalog download later)
- English first; other Steam languages when data is present

### Explicitly out of v0.1

- App Store distribution
- On-device clang kit
- AYN Thor dual-screen companion parity
- Steam achievement QR login
- 120 FPS experimental mode
- Pixel Guide integration
- Full 7th Heaven catalog browser (ship import-only first)

---

## 5. Architecture for iOS

```
ios/
  FF7Recomp/                 SwiftUI app
    App/
    Launcher/                Game files, mods, settings, saves
    GameHost/                MTKView + GameController + touch overlay
    Import/                  Document picker for GamePackage + IROs
  Engine/                    CMake / SPM wrapping shared C++
    CMakeLists.txt           iOS toolchain file
src/                         Shared with Android (submodule or copy)
  host/ hle/ mods/ ffnx_* / interp/
patches/ config/ tools/      Shared lift + FFNx patches
mac/
  ff7recomp-mac/             Companion CLI for package build
```

### Host abstraction

Introduce a thin `src/platform/` (or extend existing host files) so Android JNI
and iOS ObjC++/Swift bridging both call the same C API:

| API | Purpose |
|---|---|
| `ff7_host_create_window` | Metal layer / CAMetalLayer vs ANativeWindow |
| `ff7_host_poll_input` | GCController + touch → same button map as Android |
| `ff7_host_paths` | Application Support / Documents sandbox |
| `ff7_host_audio` | AVAudioSession + SDL3 or CoreAudio |
| `ff7_host_load_game` | `dlopen` signed dylib / static link |

Android-specific files stay under `src/android/`; new files under `src/ios/`.

### Renderer

1. Enable bgfx Metal for `arm64-apple-ios`.
2. Rebuild shaders with `shaderc` for Metal (`--platform ios -p metal`).
3. Keep Vulkan path for Android; GLES fallback not needed on modern iOS.
4. Validate: title screen → field → battle → world map on a physical device
   (simulator Metal is OK for early bring-up, not for perf).

### Audio / movies

- Port FFmpeg + SoLoud builds to iOS static libs (LGPL compliance: dynamic link
  FFmpeg or ship corresponding object files / offer LGPL notices).
- Movies stay CPU-decoded initially (same as Android).
- Respect silent switch / audio session interruptions.

---

## 6. Phased milestones

Each milestone ends with an exit test on a physical device (or Mac Catalyst
where noted).

### P0 — Repo & toolchain foundation

- Split portable core from Android Gradle/Java.
- CMake iOS toolchain (`CMAKE_SYSTEM_NAME=iOS`, bitcode off, Metal).
- Mac CLI skeleton: `validate`, `lift`, `build-package`.
- Exit: headless lift of a test exe on Mac; empty SwiftUI shell builds in Xcode.

### P1 — Metal title screen (bundled game)

- Port FFNx window/input to iOS (`android_window.cpp` → `ios_window.mm`).
- Link `FF7_BUNDLE_GAME`-style binary into the IPA for developers who have the
  exe locally (never commit generated code).
- Exit: title screen drawn by FFNx/Metal on device.

### P2 — Playable slice

- New game through Sector 7; controller + touch controls.
- Save states round-trip; PC/PS1 save import via Files.
- Exit: same playable bar as Android M2/M3, without mods.

### P3 — GamePackage workflow

- Mac CLI produces signed `libff7.dylib` + manifest (exe hash, language, build id).
- iOS app imports package via document picker; verifies hash; launches.
- Exit: clean device install → import package → Play, with no Xcode on the phone.

### P4 — Mods (import-only)

- Wire `src/mods` into the launcher; IRO/mmap union FS.
- Hext data writes; code writes via existing lift variants / interpreter.
- Exit: IFRIT + one UI mod visible in-game.

### P5 — Launcher polish & catalog

- SwiftUI parity for Settings, Get mods (Qhimm/Sega catalogs), Auto-sort.
- Background downloads, free-space checks, Wi-Fi-only option.
- Exit: install a catalog mod on device without a Mac for the mod step.

### P6 — Stretch

- Offline RetroAchievements → seek RA approval for online.
- Steam achievements (ASF/QR or Steam OpenID — research; JavaSteam won’t port).
- iPad Stage Manager / external display companion panel.
- Optional on-device build for TrollStore users.

---

## 7. Component map (Android → iOS)

| Android | iOS replacement |
|---|---|
| `LauncherActivity.java` | SwiftUI `LauncherRoot` |
| `GameActivity.java` + `SurfaceView` | `GameHostView` (`MTKView` / `UIView` + CAMetalLayer) |
| `BuildService.java` | `ff7recomp-mac` CLI + Import UI |
| `TouchControls.java` | SwiftUI overlay / SpriteKit-free UIKit overlay |
| `ModCatalog.java` / `ModLibrary.java` | Swift models + shared C++ via C bridge |
| `SaveStates.java` | Swift wrapper over same `.ff7s` format |
| `SteamLink.java` | Deferred; research Steam mobile auth |
| `CompanionView.java` | Deferred (external `UIScreen`) |
| `Storage.java` (SD card) | iOS sandbox + Files; no SD semantics |
| JNI `ff7_launcher_jni.cpp` | `@_cdecl` / ObjC++ bridge module |
| Gradle + NDK | Xcode + CMake + (optional) Swift Package |

---

## 8. Distribution & policy

| Channel | Reality |
|---|---|
| App Store | Extremely unlikely: commercial game reimplementation tooling, user-supplied binaries, GPL-3.0 (FFNx), and “emulator-like” heuristics |
| TestFlight (private) | Possible for closed testers if the binary does not include game code; still review-sensitive |
| AltStore / SideStore | Primary public path for enthusiasts |
| TrollStore / jailbreak | Enables closer Android parity (on-device link) |
| Direct IPA + Apple Developer cert | Best for the original author / friends |

Ship **GPL-3.0** (same as Android) and keep `game/`, `generated/`, `analysis/`
out of git. Document that users must own the Steam release.

---

## 9. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Codesign blocks any on-device lib | High | Mac companion is the product design, not a workaround |
| bgfx Metal edge cases with FFNx | High | Title-screen milestone early; keep Android Vulkan as reference |
| Guest memory below 2 GB assumption | Medium | Verify `vm_allocate` fixed addresses on iOS; may need entitlement or remapping strategy |
| Huge game + mod storage in sandbox | Medium | Files app / “Move to …”; warn on free space; prefer keeping assets in user-visible Documents |
| FFmpeg LGPL + static link | Medium | Dynamic framework or provide LGPL compliance artifacts |
| Hext code patches without re-lift | Medium | Keep x86 interpreter path from Android |
| Performance vs Thor | Medium | Target 60 FPS on A15+; profile movies and 3D battles |
| Steam / RA integrations | Low for MVP | Ship local achievements first |

---

## 10. Suggested first implementation slice

Do not start with the full launcher. Build this vertical slice:

1. CMake iOS + empty SwiftUI app that links `ff7_core` stubs.
2. Mac script: lift + compile bundled game for device (developer-only).
3. Metal window + FFNx boot → title screen.
4. One settings screen + Play button.

That proves the port is real before investing in catalogs, dual-screen, or Steam.

---

## 11. Open decisions

1. **Monorepo vs fork:** extend the Android repo with `ios/` + `mac/`, or a
   sibling `ff7-recomp-ios` that submodules the core?
2. **Package format:** single signed dylib + JSON manifest, or an `.ff7pkg`
   archive with data pointers (game data still copied separately)?
3. **Minimum device:** iPhone 12 / A14 vs A15+ for 60 FPS headroom?
4. **Mac Catalyst:** ship a Mac playable build as the daily driver before iPhone?
5. **Interpreter-first demo:** ship a slow “no Mac required” mode for demos?

---

## 12. References

- Android project: https://github.com/bhuiyah/ff7-recomp-android
- FFNx: https://github.com/julianxhokaxhiu/FFNx
- pcrecomp: https://github.com/sp00nznet/pcrecomp
- Android docs: `docs/FFNX_PORT.md`, `docs/ROADMAP.md`, `docs/SAVESTATES.md`
- bgfx Metal: https://bkaradzic.github.io/bgfx/
