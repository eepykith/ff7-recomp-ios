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

## Next link step

```bash
bash tools/fetch_android_core.sh
```

That clones [ff7-recomp-android](https://github.com/bhuiyah/ff7-recomp-android)
under `external/` (gitignored). Wiring `cmake/ffnx.cmake` to Metal, and calling
`ff7_boot_and_run` on a background thread with a 64 MB stack (as Android does),
is the remainder of P1. Do not commit anything under `external/`, `generated/`,
or `game/`.
