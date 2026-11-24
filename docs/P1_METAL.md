# P1 — Metal surface

The iOS play view now owns a `CAMetalLayer` and publishes it through the same
C ABI Android uses for bgfx.

| Android | iOS |
|---|---|
| `ANativeWindow *` from `GameActivity.nativeSetSurface` | `CAMetalLayer *` from `FF7MetalView` |
| `ff7_platform_window()` | same symbol, `src/platform/ff7_platform.c` |
| XInput pad from key/motion events | `ff7_platform_set_pad()` from the on-screen pad |
| `ff7_boot_and_run()` on a game thread | weak symbol; absent until FFNx is linked |

Until that symbol is linked, `FF7MetalView` clears the drawable itself:

- warm dark — no GamePackage
- blue — package noted, FFNx not linked
- black — a linked engine owns the frame (`ff7_engine_owns_present`)

That blue frame is the P1 bring-up, not FF7's title screen. The title screen
needs your Steam `ff7_en.exe`, a Mac lift, and FFNx built for Metal.

## On a Mac

```bash
cd ios && xcodegen generate && open FF7Recomp.xcodeproj
```

Run on an iPhone or simulator. Open **Play**. You should see a live blue (or
warm, if nothing is imported) Metal view and the touch pad. The status line
says FFNx is not linked.

## Next link step (Mac)

```bash
bash tools/fetch_android_core.sh
bash tools/setup_android_core.sh
bash tools/apply_metal_overlay.sh

# Steam 2026 install (contains ff7/resources/ff7_1.02/ff7_en):
STEAM="$HOME/Library/Application Support/Steam/steamapps/common/FINAL FANTASY VII Steam Edition"
python3 -I external/ff7-recomp-android/tools/import_game.py "$STEAM"

# Lift (writes gitignored generated/ under the Android tree):
AND=external/ff7-recomp-android
mkdir -p "$AND/analysis"
gunzip -c "$AND/config/catalog.json.gz" > "$AND/analysis/catalog.json"
python3 -I "$AND/tools/run_lift.py" lift "$AND/game/ff7_en.exe" \
  "$AND/analysis/catalog.json" "$AND/generated/recomp"
python3 -I "$AND/tools/gen_extents.py" "$AND/generated/recomp"
python3 -I "$AND/tools/gen_retn_table.py"

# Native arm64 (no Rosetta): the guest lives in a window at g_mem_base (FF7_BASED_MEMORY).
cmake -S . -B build-metal-arm64 -DFF7_BUNDLE_GAME=ON -DFF7_PLATFORM=mac \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DFF7_BUILD_TESTS=OFF -DFF7_BASED_MEMORY=ON
cmake --build build-metal-arm64 -j --target ffnx ff7_core ff7_platform
FF7_BUILD_DIR=$PWD/build-metal-arm64 bash tools/darwin_link_metal_boot.sh
make -C "$AND/external/bgfx" shaderc
bash tools/compile_shaders_metal.sh
cp "$AND/external/FFNx/misc/FFNx.toml" ./FFNx.toml
FF7_QUICKBOOT=title ./build-metal-arm64/ff7_metal_boot game

# Rosetta x86_64 flat build (the first bring-up; still works, g_mem_base stays 0):
cmake -S . -B build-metal-x64 -DFF7_BUNDLE_GAME=ON -DFF7_PLATFORM=mac \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 -DFF7_BUILD_TESTS=OFF
cmake --build build-metal-x64 -j --target ffnx ff7_core ff7_platform
bash tools/darwin_link_metal_boot.sh   # FF7_BUILD_DIR defaults to build-metal-x64
FF7_QUICKBOOT=title ./build-metal-x64/ff7_metal_boot game
```

`FF7_QUICKBOOT=title` presses Start through the credits and stops on the title screen. Without
FFmpeg (`tools/build_ffmpeg_apple.sh`) the intro movies are no-op stubs and the credits never
advance on their own. `FF7_QUICKBOOT=newgame` skips the opening movie unless
`FF7_QUICKBOOT_KEEP_FMV=1`; `FF7_DSOUND_STATS=1` logs the sound-effect mixer's CoreAudio output. `FF7_SNAPSHOT=/path/shot.png` writes the window to a PNG every 5 s
(same-process capture; no Screen Recording grant needed).

`ff7_host_boot` starts `ff7_boot_and_run` on a **64 MB** detached pthread
(`src/ios/ff7_ios_boot.c`). Do not commit `external/`, `generated/`, or `game/`.

### Reproducing `external/`

`external/` is never committed; this repo rebuilds it exactly:

```bash
bash tools/fetch_android_core.sh     # core pinned at 7218386
bash tools/setup_android_core.sh     # nested repos pinned + the Android port's patches/transforms
bash tools/apply_metal_overlay.sh    # Metal overlay, based memory, then patches/*.patch
```

`apply_metal_overlay.sh` ends with `patches/android-core-darwin.patch`,
`patches/pcrecomp-darwin.patch` and `patches/ffnx-darwin.patch`: the Darwin edits made by hand
during the first bring-up (thread ids, `MAP_FIXED_NOREPLACE`, stack bounds, the DirectSound
mixer's CoreAudio output (`src/hle_overlay/ff7_dsound_coreaudio.c`), Apple-mangled link stubs, Metal as FFNx's renderer, NEON by target arch, the
`malloc.h` shim, bring-up logging). Every step is idempotent. Checked by replaying from
pristine sources into a scratch tree: identical to the working tree, file for file, apart from
the two cmake lines that name this repo's own path.

### Darwin status (P1 bring-up)

| Piece | Status |
|---|---|
| Fetch Android core + deps / FFNx transforms | Works (`tools/setup_android_core.sh`) |
| Import Steam 2026 `ff7_en` + `data/` | Works (gitignored under `game/` / `external/.../game/`) |
| Lift → `generated/recomp` | Works (~25k functions) |
| bgfx Metal static libs | Works (`tools/apply_metal_overlay.sh`) |
| `ff7_core` + `libffnx.a` compile | Works |
| 64 MB game thread API | Wired in `src/ios/ff7_ios_boot.c` |
| Final `ff7_metal_boot` link | Works on **native arm64** (based memory) and **Rosetta x86_64** (flat) via `tools/darwin_link_metal_boot.sh` |
| Guest arena + PE map | Native arm64: guest window at `g_mem_base` (4 GB aligned); Rosetta: flat at `0x400000` |
| CAMetalLayer window | Works (`src/mac/ff7_mac_metal_window.mm`) |
| Metal shaders (`*.mtl.*`) | Works (`tools/compile_shaders_metal.sh`) |
| Title screen | **Works on Mac, native arm64 and Rosetta x86_64**: FFNx logo, then the title (New Game / Continue) |
| iOS simulator | **Works**: `FF7RecompBundled` links the core and reaches the title (see "iOS app") |
| iOS device | Core (`tools/build_ios_core.sh device`) and `FF7RecompBundled` build and link for `iphoneos` (unsigned); not yet run on hardware: needs a signing team, the game files, and the address-space check |

Steam folder used here:
`~/Library/Application Support/Steam/steamapps/common/FINAL FANTASY VII Steam Edition`
(not the docs placeholder `/path/to/FINAL FANTASY VII`).

### Bring-up fixes that got the title on screen

- **Rosetta abort `invalid Mach-O magic`.** With the 0x1000 PAGEZERO, the Rosetta runtime,
  `libobjc-trampolines` and its `.aot` image loaded inside the PE range (0x400000–0xF6F000),
  and `pe_loader`'s `MAP_FIXED` overwrote them. `src/mac/ff7_guest_reserve.s` adds a zero-fill
  `__FF7GUEST` segment pinned at 0x400000 (`-segaddr`, in `tools/darwin_link_metal_boot.sh`),
  so that range belongs to the executable from exec.
- **Engine ran but the layer never got a frame.** `Renderer::setPostprocessingBackend` /
  `setYUVMovieBackend` live in FFNx `video/ntscj.cpp`, which is only built with FFmpeg, and were
  replaced by empty stubs. FFNx's final blit then went to its offscreen framebuffer and bgfx
  never asked the layer for a drawable. `src/ffnx_overlay/renderer_srgb_backends.cpp` supplies the
  real selectors, and `tools/apply_metal_overlay.sh` builds it in and drops the stubs.
- **Pad inject was sticky.** `ff7_platform_pad_inject` ORed into the player's pad and never
  released. It now keeps a separate mask, as on Android.

### iOS app (simulator)

`ios/project.yml` has two targets. `FF7Recomp` is the launcher shell alone. `FF7RecompBundled`
links the whole core (your lift, the runtime, FFNx, bgfx/Metal) with `FF7_BUNDLE_GAME`, and
boots its game folder, `Library/Application Support/FF7Recomp/game`.

```bash
bash tools/build_ios_core.sh simulator    # -> build-ios-sim/libff7_bundle.a (based memory)
cd ios && xcodegen generate
xcodebuild -scheme FF7RecompBundled -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath ../build-ios-dd build
xcrun simctl install booted ../build-ios-dd/Build/Products/Debug-iphonesimulator/FF7RecompBundled.app
bash ../tools/ios_sim_link_game.sh        # the app's game folder -> ../game (symlink; simulator only)
SIMCTL_CHILD_FF7_QUICKBOOT=title xcrun simctl launch --console-pty booted com.ff7recomp.ios
```

Tap **Play**: the title screen draws on the play view's `CAMetalLayer`. The app links strictly
(no `-undefined dynamic_lookup`). With `tools/build_ffmpeg_apple.sh ios-simulator` built first,
FFNx's real movie player is linked in; otherwise `src/ffnx_overlay/ffmpeg_movie_stubs.cpp` stands
in for it and every movie ends on its first frame. Simulator only, arm64
(Apple silicon).

Known gaps: the 4:3 frame is stretched to the play view, and the swapchain keeps the size it
booted with when the device rotates (P2: lock the play view to landscape and pass FFNx the
view's size). On a device the game files must be imported for real (Game files in the app), the
app needs a signing team, and the 2 GB guest reservation (plus 4 GB alignment slack) may need
the `com.apple.developer.kernel.extended-virtual-addressing` entitlement.

### Based memory (native arm64)

Native arm64 processes (macOS, iOS, the simulator on Apple silicon) keep a 4 GB PAGEZERO, so
the flat layout (guest address == host address below 4 GB) is impossible there.
`-DFF7_BASED_MEMORY=ON` builds the lift without `RECOMP_FLAT_MEMORY`: every lifted access is
`g_mem_base + va`. `ff7_guest_window_init()` (`ff7_boot.c`) reserves the guest's
`[0, 0x80000000)` as one `PROT_NONE` window, **4 GB aligned**, so a host pointer into it
truncates to its guest address and only guest → host needs the base.

The host side (Win32 shims, FF7 HLE, FFNx) is converted by `tools/based_memory_port.py`, run
from `tools/apply_metal_overlay.sh`:

- `G2H(va)` / `H2G(p)` (in pcrecomp's `recomp_types.h`). `G2H(0)` is `NULL`, and with
  `g_mem_base == 0` both are the old casts, so flat builds (Android, Rosetta) are unchanged.
- Regex passes over `(T *)(uintptr_t)X`, `reinterpret_cast<T *>(static_cast<uintptr_t>(X))`,
  FFNx's `(T *)get_absolute_value(...)` and literal-address casts, plus a short list of edits
  (fixed `mmap`s, `guest_abi.h`'s `gptr` conversions, `put_arg`'s guest-pointer test, `strcpy_s`).
- `patches/ffnx-based-memory.patch`: the FFNx sites clang found with `-Wint-to-pointer-cast` and
  `-Wformat` (a `gptr<char>` passed to `%s` arrives as its raw guest address), generated with
  `based_memory_port.py warnings|formats` on FFNx `0adf0b32`.

A guest address the port missed is dereferenced below 4 GB, which is PAGEZERO: it faults at
once, and lldb shows the exact site.

The same based core runs in the iOS simulator ("iOS app" above). For a device, what remains is
signing, and checking that the 2 GB `PROT_NONE` reservation (plus 4 GB of alignment slack,
released right away) fits the app's address space; iOS may need the
`com.apple.developer.kernel.extended-virtual-addressing` entitlement.
