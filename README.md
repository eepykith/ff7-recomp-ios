# FF7Recomp iOS — Port Plan

Planning docs for an iOS version of
[FF7Recomp for Android](https://github.com/bhuiyah/ff7-recomp-android): native
ARM64 FINAL FANTASY VII (Steam PC) via static recompilation + FFNx, with a
7th Heaven–style mod launcher. **No game files are included.**

## Read this first

The full plan is in **[docs/IOS_PORT_PLAN.md](docs/IOS_PORT_PLAN.md)**.

**Short version:** an iOS port is feasible as a **sideloaded** native app, but
Android’s on-device clang build cannot be copied. iOS codesigning forces a
**Mac companion** that lifts and signs the user’s `ff7_en.exe`, then the iOS
app imports that package and runs FFNx on **Metal**.

## What’s in this repo

| Path | Contents |
|---|---|
| `docs/IOS_PORT_PLAN.md` | Architecture, blockers, milestones, Android→iOS map |
| `README.md` | This file |

Implementation (SwiftUI host, CMake iOS toolchain, Mac CLI) is not started yet.
Use the plan’s **P0 / first slice** when you’re ready to build.

## Legal

Same model as the Android project: you need your own Steam copy of FINAL
FANTASY VII. Not affiliated with or endorsed by Square Enix.
