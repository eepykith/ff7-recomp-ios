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

# Native arm64 cannot shrink PAGEZERO (kernel SIGKILL), so guest flat 32-bit
# VAs need Rosetta x86_64 until a non-flat memory model exists:
cmake -S . -B build-metal-x64 -DFF7_BUNDLE_GAME=ON -DFF7_PLATFORM=mac \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 -DFF7_BUILD_TESTS=OFF
cmake --build build-metal-x64 -j --target ffnx ff7_core ff7_metal_boot || true
bash tools/darwin_link_metal_boot.sh   # FF7_BUILD_DIR defaults to build-metal-x64
make -C "$AND/external/bgfx" shaderc
bash tools/compile_shaders_metal.sh
cp "$AND/external/FFNx/misc/FFNx.toml" ./FFNx.toml
FF7_QUICKBOOT=title ./build-metal-x64/ff7_metal_boot game
```

`FF7_QUICKBOOT=title` presses Start through the credits and stops on the title screen. FFmpeg
is not built for Darwin yet, so the intro movies are no-op stubs and the credits never
advance on their own. `FF7_SNAPSHOT=/path/shot.png` writes the window to a PNG every 5 s
(same-process capture; no Screen Recording grant needed).

`ff7_host_boot` starts `ff7_boot_and_run` on a **64 MB** detached pthread
(`src/ios/ff7_ios_boot.c`). Do not commit `external/`, `generated/`, or `game/`.

### Darwin status (P1 bring-up)

| Piece | Status |
|---|---|
| Fetch Android core + deps / FFNx transforms | Works (`tools/setup_android_core.sh`) |
| Import Steam 2026 `ff7_en` + `data/` | Works (gitignored under `game/` / `external/.../game/`) |
| Lift → `generated/recomp` | Works (~25k functions) |
| bgfx Metal static libs | Works (`tools/apply_metal_overlay.sh`) |
| `ff7_core` + `libffnx.a` compile | Works |
| 64 MB game thread API | Wired in `src/ios/ff7_ios_boot.c` |
| Final `ff7_metal_boot` link | Works on **Rosetta x86_64** via `tools/darwin_link_metal_boot.sh` (CMake-object dedupe + `dynamic_lookup` + small PAGEZERO + high `image_base`) |
| Guest arena + PE map at `0x400000` | Works under Rosetta |
| CAMetalLayer window | Works (`src/mac/ff7_mac_metal_window.mm`) |
| Metal shaders (`*.mtl.*`) | Works (`tools/compile_shaders_metal.sh`) |
| Title screen | **Works on Mac (Rosetta x86_64)**: FFNx logo, then the title (New Game / Continue) on the CAMetalLayer |
| iOS device / simulator | **Not yet** — both are native arm64, which cannot map the flat 32-bit guest (see below) |

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

### What blocks iOS (device and simulator)

The lifted code addresses guest memory as flat 32-bit host pointers (PE at 0x400000, arena at
0x33000000). Native arm64 processes, including every iOS process and the simulator on Apple
silicon, keep a 4 GB PAGEZERO that cannot be shrunk, so those addresses can never be mapped.
The Mac host gets around this only by running x86_64 under Rosetta, which iOS lacks. Reaching
the title on iOS needs a based memory model in the lifter/runtime (every guest access
`MEM32(va)` → `guest_base + va`), not more host work.
