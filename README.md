<p align="center">
  <img src="docs/media/hero-banner.png" alt="FF7Recomp for iOS — green Materia over a Midgar skyline under a starfield and orange meteor" width="100%">
</p>

# FF7Recomp for iOS

[![Release](https://img.shields.io/github/v/release/eepykith/ff7-recomp-ios?include_prereleases&label=release&color=2ea44f)](https://github.com/eepykith/ff7-recomp-ios/releases/latest)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20(sideload)-111111)](https://github.com/eepykith/ff7-recomp-ios/releases)
[![Builder](https://img.shields.io/badge/Mac%20Builder-Apple%20silicon-black)](https://github.com/eepykith/ff7-recomp-ios/releases)

**FINAL FANTASY VII on iPhone — native ARM64, Metal, your Steam copy.**

An iOS port of [FF7Recomp](https://github.com/bhuiyah/ff7-recomp-android): the Steam PC game is
statically recompiled to ARM64 and drawn by [FFNx](https://github.com/julianxhokaxhiu/FFNx) on
Metal. Touch controls, Bluetooth controllers, an iPhone Duo layout with a status panel, and a
launcher for saves and mods.

> [!IMPORTANT]
> **No game is included.** You build an IPA from **your own Steam copy** of FINAL FANTASY VII with
> **FF7Recomp Builder** ([download](https://github.com/eepykith/ff7-recomp-ios/releases)). The Mac
> lifts and packs the game once; iOS cannot compile on-device.

> [!NOTE]
> **Pre-release** ([v0.2.3d](https://github.com/eepykith/ff7-recomp-ios/releases/tag/v0.2.3d)) on
> an **iPhone Duo**: tested through the first reactor; full game expected playable. Includes mods
> from 7th Heaven catalogs. Still a pre-release — expect rough edges. Sideload only — not the App
> Store.

---

## Contents

- [Screenshots](#screenshots)
- [Requirements](#requirements)
- [Get started](#get-started)
- [Install on iPhone (sideloading)](#install-on-iphone-sideloading)
- [On your iPhone](#on-your-iphone)
- [What works](#what-works)
- [Mods](#mods)
- [Known gaps](#known-gaps)
- [Roadmap](#roadmap)
- [How it works](#how-it-works)
- [Credits](#credits)
- [Legal](#legal)

---

## Screenshots

Built with FF7Recomp Builder from the player's own Steam copy; played by touch in the simulator
and on device.

<table>
<tr>
<td width="40%"><img src="docs/screenshots/duo-portrait.jpg" alt="iPhone Duo open and upright in No. 5 Reactor: the 16:9 game in the top half; below, the status panel with Cloud, Barret and Tifa, quick buttons, and the touch pad at the sides"></td>
<td>

### iPhone Duo — upright

Open or half-folded and held upright: the game sits in the **top half**, clear of the fold. Below
it, a companion status panel shows location, play time, gil, and each member's HP, MP, and Limit
(ATB and enemy HP in battle), plus quick buttons — Menu, save/load state, speed 1×/2×/3×, random
battles, Battle+.

The touch pad stays in the side columns, d-pad and face buttons high where thumbs reach. With a
controller connected, the pad hides (Settings → Controls).

</td>
</tr>
</table>

| iPhone Duo open, landscape (16:9) | iPhone Duo closed (outer screen) |
| :---: | :---: |
| ![iPhone Duo open in landscape: the 16:9 picture across the full width, the see-through pad over its edges](docs/screenshots/duo-open-landscape.jpg) | ![iPhone Duo closed: the 16:9 game on the outer screen with the pad clear of the camera](docs/screenshots/duo-closed.jpg) |
| **Widescreen**: the picture fills the width; see-through pad over the edges. | Outer screen goes landscape; pad clear of the camera. |

| Regular iPhone (landscape) |
| :---: |
| ![iPhone 18 Pro in landscape: the 16:9 picture nearly edge to edge, the pad over it](docs/screenshots/iphone18pro.jpg) |
| 16:9 fills an iPhone almost edge to edge. Round d-pad, big **OK** / **Back**; slide without lifting; multi-touch. |

<table>
<tr>
<td width="40%"><img src="docs/screenshots/duo-guide.jpg" alt="iPhone Duo upright: the game on top, a text walkthrough open in the status panel's place, the pad at the sides"></td>
<td>

### Guide beside the game

📖 opens your guide in the status panel's place: read and scroll while you play. **Find guides
on GameFAQs** saves one for offline reading, or add your own TXT, HTML or PDF. Each guide keeps
your place. On one screen it opens full screen and the game pauses.

</td>
</tr>
</table>

| Your pad, your way | Buttons shown | Settings |
| :---: | :---: | :---: |
| ![Size and layout: the pad over a stand-in for the game, OK selected with a slider to resize it](docs/screenshots/pad-layout.jpg) | <img src="docs/screenshots/buttons-shown.jpg" alt="Buttons shown: D-pad, OK, Back, Menu, Switch, L1, R1, Select, Start, each with a switch" width="260"> | <img src="docs/screenshots/settings.jpg" alt="Settings: Appearance System/Light/Dark, Picture 16:9 widescreen, Frame rate, On-screen pad, Buttons shown, Size and layout" width="260"> |
| **Size and layout**: drag to move, tap one to resize; kept for each way you hold the iPhone. | Hide any button; it still works on a controller. | Widescreen or 4:3, frame rate, light/dark launcher. |

| Mods | Get Mods | A catalog mod |
| :---: | :---: | :---: |
| <img src="docs/screenshots/mods.jpg" alt="Mods: Get Mods on top, the installed mods numbered in load order with on/off switches" width="260"> | <img src="docs/screenshots/getmods.jpg" alt="Get Mods: 7th Heaven's catalogs, 115 mods, All / Installed / Updates" width="260"> | <img src="docs/screenshots/moddetail.jpg" alt="Echo-S in Get Mods: preview, category, author, version, size, Install" width="260"> |
| Numbered load order; the first wins. Drag to reorder; switch each on or off. | 7th Heaven's Qhimm and Sega catalogs: search, categories, updates. | Preview and details; **Install** downloads it in the background. |

| Touch and hold a mod | Mod options |
| :---: | :---: |
| <img src="docs/screenshots/modmenu.jpg" alt="Touch and hold a mod: Options and Delete" width="260"> | <img src="docs/screenshots/modoptions.jpg" alt="Compact Battle UI options: switched on, Battle UI Style" width="260"> |
| **Options…** or **Delete**. | The mod's own settings, applied the next time the game starts. |

| First launch | FF7Recomp Builder (Mac) | Download from Steam |
| :---: | :---: | :---: |
| <img src="docs/screenshots/setup.jpg" alt="First launch: game files confirmed, Play" width="260"> | ![FF7Recomp Builder: your game found and checked, Xcode found, Build FF7Recomp.ipa](docs/screenshots/mac-builder.jpg) | ![Download from Steam: sign in once with a QR code; downloaded game files kept for the next build, with Remove](docs/screenshots/mac-steam.jpg) |
| Confirms your Steam game files, then **Play**. Mods unlock after confirm. | Finds Steam or your download, checks the copy, builds **FF7Recomp.ipa**. Apple silicon and Intel. | Sign in once with a QR code in the Steam app; the game files come straight from Steam. |

---

## Requirements

| You need | Details |
| --- | --- |
| **Mac** | Apple silicon or Intel, macOS 14 or later. |
| **Xcode** | From the Mac App Store; open it once after install. |
| **FINAL FANTASY VII on Steam** | Current Steam Edition (`ff7` layout). No older patch; patched installs are not supported. |
| **Sideloading** | Development profile, [AltStore](https://altstore.io/), [SideStore](https://sidestore.io/), or similar. |

---

## Get started

### 1. Download the Builder

Grab **FF7Recomp Builder** from
[Releases](https://github.com/eepykith/ff7-recomp-ios/releases), unzip it, and open it.

> [!TIP]
> The Builder is **not notarized** yet. First launch: right-click → **Open**, or System Settings →
> Privacy & Security → **Open Anyway**.

### 2. Build your IPA

1. Get the game files, either way:
   - **Download from Steam…**: sign in once by scanning a QR code with the Steam app on your
     phone (Steam Guard › Scan a QR code; you never type your Steam password into the Builder).
     The Builder downloads the files your Steam account owns (about 3.6 GB) straight from Steam
     and checks each one. No Mac Steam app needed. If the download stops, press it again: it goes
     on where it was.
   - Or use your Steam install: the Builder finds it, or **Choose…** its folder.
2. It checks the game is as Steam sells it today (no patches) and that Xcode is present.
3. Click **Build FF7Recomp.ipa…** — it lifts the game to C, compiles for iPhone, links the
   engine, and packs your game files.

The first build takes a few minutes. The IPA is about **3 GB**.

### 3. Sign and install

Sideload the IPA onto your iPhone (not the App Store). See
[Install on iPhone (sideloading)](#install-on-iphone-sideloading) for SideStore, AltStore,
Sideloadly, and similar tools.

### 4. Play

Open **FF7Recomp** → confirm game files → **Play**.

> [!CAUTION]
> The IPA contains the game built from **your** copy and **your** game files. It is for **your
> own devices only. Never share it.** The Builder itself ships no game code and no game files.

Building the project from source (contributors / developers): see
[`docs/BUILDING.md`](docs/BUILDING.md).

---

## Install on iPhone (sideloading)

FF7Recomp is **sideload only** — it is not on the App Store. You install the **IPA you built**
from your own Steam copy with FF7Recomp Builder. Pick any resign/install tool you already trust;
the notes below are the usual paths.

> [!WARNING]
> When the tool **re-signs** the IPA, keep
> **`com.apple.developer.kernel.extended-virtual-addressing`** (extended virtual addressing).
> The game reserves a 4 GB address window; dropping that entitlement often breaks launch. If the
> UI has an entitlements list or “keep entitlements” option, leave it on / do not strip it.

> [!TIP]
> **No FF7Recomp folder in Files › On My iPhone?** Some signing apps drop the app's Files
> sharing when they re-sign. Re-sign with **file sharing / document browser** support turned on
> (the option's name varies) and install over the top; your saves, mods and guides stay.

> [!CAUTION]
> The IPA is for **your devices only**. Do not upload it to public IPA libraries or share it.

### SideStore

1. Install [SideStore](https://sidestore.io/) on your iPhone (follow their current pairing /
   refresh setup).
2. Copy your `FF7Recomp.ipa` to the phone (Files, AirDrop, cloud folder, etc.).
3. In SideStore → **My Apps** (or equivalent) → install from that IPA.
4. Confirm extended virtual addressing stayed on the signed app if SideStore shows entitlements.
5. Refresh / keep SideStore’s signing alive as their docs describe (free Apple IDs expire on a
   short cycle).

### AltStore

1. Run [AltServer](https://altstore.io/) on your computer and install **AltStore** on the iPhone.
2. Put `FF7Recomp.ipa` in Files on the device (or open it from AltStore’s import flow).
3. In AltStore, install the IPA.
4. Keep extended virtual addressing when AltStore resigns; refresh via AltServer as needed.

### Sideloadly

1. On a Mac or Windows PC, open [Sideloadly](https://sideloadly.io/), connect the iPhone, and
   sign in with your Apple ID when asked.
2. Drop in `FF7Recomp.ipa`.
3. Before installing: if there is an entitlements / “live container” / advanced options panel,
   **keep** extended virtual addressing — do not use a mode that strips custom entitlements.
4. Start the install and wait for the app to appear on the Home Screen. Trust the developer in
   Settings → General → VPN & Device Management if iOS asks.

### Other options

| Tool | High-level |
| --- | --- |
| **Xcode** (free or paid Apple Developer) | Open/import the signed app or use a development profile you control; install to a paired device. Same entitlement rule. |
| **Other resign utilities** | Same idea: sign the Builder IPA for your team/Apple ID and install over USB or Wi‑Fi. Prefer tools that preserve existing entitlements. |

Free personal Apple IDs used with SideStore / AltStore / Sideloadly typically need periodic
**refresh** or reinstall when the short signing window ends. A paid Apple Developer account lasts
longer. Exact UI labels change — when in doubt, check that tool’s docs and the entitlement
warning above.

---

## On your iPhone

### Files

In the **Files** app → **On My iPhone › FF7Recomp**:

| Folder | Contents |
| --- | --- |
| `Saves` | Game saves (`save00.ff7` …) |
| `Save States` | Save states (status panel Save/Load, or Select+L1 / Select+R1) |
| `Mods` | 7th Heaven mods (`.iro` / folders) and load order (`profile.xml`) |
| `Guides` | Your own game guides (TXT, HTML, PDF) for the 📖 guide reader |
| `Logs` | Logs to share when reporting a problem |

Use these folders to back up, move between devices, or add files by hand.

### Controls

| Input | Notes |
| --- | --- |
| **Touch pad** | See-through buttons: a round d-pad (8-way) and big **OK** (B) / **Back** (A) with **Menu** (Y) / **Switch** (X) above. Slide across them without lifting; multi-touch. Pick which buttons show (Settings → Controls → Buttons shown) and move or resize them (Size and layout, kept for each way you hold the iPhone). |
| **Bluetooth controller** | Supported. Pad hide modes: Settings → Controls (hide with controller / always / never). |
| **Quit** | ✕ → Quit exits the app (one game session per launch). Reopen FF7Recomp to play again. |
| **Guide** | 📖 beside ✕: **Find guides on GameFAQs** opens its Final Fantasy VII guide list; **Save guide** keeps one for offline reading. Or add your own TXT / HTML / PDF guides (Files › FF7Recomp › Guides). On the iPhone Duo upright it takes the status panel's place while you play; otherwise it opens full screen and the game pauses. Keeps your place; find and text size. |

### iPhone Duo

| Pose | Layout |
| --- | --- |
| Open / half-folded, upright | Game in top half; status panel + pad below, d-pad and face buttons high in the side columns |
| Landscape or closed | Game fills the active screen |

---

## What works

On an **iPhone Duo**: tested through the first reactor; full game expected playable.

- Field, battles, menus, **movies**, music & SFX
- Saves and save states
- Touch pad and Bluetooth controllers; the pad's buttons shown, size and layout are yours to set
- Duo folded / half-folded / open layouts
- Files-app folders for saves, states, and mods
- **Get Mods** — Qhimm & Sega catalogs; download `.iro` / `.zip` / `.7z` (incl. Google Drive);
  conflict warnings; touch-and-hold for options, move up / down, delete
- **Mod order** — drag mods into order (iOS 27; Edit on earlier iOS); numbered, the first wins
- **Share logs / Report a problem** (Settings › Help) — one zip of the logs, device and mods for a
  GitHub issue; offered after a crash; logs also in Files › FF7Recomp › Logs
- **Widescreen** (Settings › Display › Picture): 16:9 by default: battles, the world map and wide field screens fill the width; menus stay 4:3 in the middle, and fields without wide backgrounds keep narrow side bars. 4:3 original is one tap away
- **Appearance** (Settings): the launcher follows the iPhone's light / dark mode, or stays light or dark
- **Guide reader** (📖 in play): save GameFAQs guides in the app or add your own TXT, HTML or PDF; beside the game on the Duo, full screen on one screen; keeps your place
- **Frame rate** (Settings): original / fixed / 30 FPS battles / 60 / experimental **120** on
  120 Hz screens
- Background / calls pause the game; silent switch mutes

---

## Mods

Browse **Get Mods** in the app, or drop archives into the `Mods` folder. Load order follows
`profile.xml` in the Mods list.

### Tested together (iPhone Duo, 0.2.x)

Eight mods enabled at once (~63k replaced files), with save states in a short playthrough:

| Mod | Category | Status | Notes |
| --- | --- | --- | --- |
| [Tsunamods] Echo-S 7 | Gameplay | ✅ | 3.2 GB; code patches apply |
| [Tsunamods] Enhanced Stock UI | UI | ✅ | |
| [Tsunamods] Cosmo Memory | Media | ✅ | |
| [Tsunamods] SYW Unified Field Textures | Field | ✅ | Black backgrounds after save-state load fixed in 0.2.3 |
| [Tsunamods] SYW Unified Battle Textures | Battle | ✅ | |
| [Tsunamods] SYW Unified Spell Textures | Spell | ✅ | |
| NinoStyle HD Field Models | Field Models | ✅ | |
| NinoStyle Battle Models | Battle Models | ✅ | |
| Jessie Mod | Misc | ✅ | Simulator only; Options… works |

✅ no issues · ⚠️ works with issues · ❌ doesn't work

Tried a mod? [Open an issue](https://github.com/eepykith/ff7-recomp-ios/issues) with how it went.

> [!NOTE]
> With this stack, FFNx.log may mention a missing field piece (`AUGC1.RSD`). Nothing wrong on
> screen so far. **Not in-app yet:** Mega / forum downloads (use Safari + **Import Mods**), and
> **RAR** archives.

---

## Known gaps

| Area | Status |
| --- | --- |
| Non-Duo iPhone / iPad | Untested (simulator + Duo only) |
| Builder notarization | Open — Gatekeeper “Open Anyway” on first launch |
| Intel Mac Builder | Tested under Rosetta on Apple silicon; not yet on an Intel Mac itself |
| Mega / forum / RAR mod downloads | Manual Safari + Import; RAR refused |
| Quit | Exits the app (by design for now) |

---

## Roadmap

Planned by version. Order may change as reports come in.

### 0.4 — A polished launcher
|Item|Plan|
|---|---|
|**Aesthetics**|Home screen art; smoother Get Mods / Mods; clearer first launch|
|**More devices**|Regular iPhones and iPads beyond the Duo|
|**Game Center achievements**|The game's 32 achievements; system pop-ups and Game Center profile|

### 0.5 — Mac app, iCloud sync, MetalFX, and haptics
|Item|Plan|
|---|---|
|**Mac game app**|Same builder, from your Steam copy|
|**iCloud sync**|Saves, save states, and mods across Mac, iPhone, and iPad|
|**MetalFX upscaling**|Lower-res draw + Metal upscale; less heat / longer battery (or sharper), esp. HD textures|
|**Controller haptics**|Xbox / DualSense rumble; DualSense adaptive triggers; Taptic Engine on the touch pad|

### Toward 1.0
|Item|Plan|
|---|---|
|**HDR (EDR)**|Brighter magic / Mako highlights on supported iPhone and iPad screens|
|**External display**|Game on TV/monitor over USB-C; iPhone as controller and status panel|
|**Also**|Display settings (filters), Steam Cloud saves, in-app install help|

---

## How it works

- **Static recompilation** — `ff7_en.exe` (32-bit x86) is lifted to C and compiled for ARM64.
  Win32 is replaced by a thin host layer; guest memory lives in a 4 GB–aligned window.
- **Rendering & audio** — [FFNx](https://github.com/julianxhokaxhiu/FFNx) via bgfx → **Metal**;
  movies with FFmpeg; music with SoLoud; SFX through CoreAudio.
- **Core** — from the Android port, fetched pinned and patched for Apple (`tools/`, `patches/`).

Contributor / from-source builds: **[`docs/BUILDING.md`](docs/BUILDING.md)**.

---

## Credits

Rendering, movies, timing fixes, and the modding surface in this port come from
**[FFNx](https://github.com/julianxhokaxhiu/FFNx)** — the next-generation FINAL FANTASY VII / VIII
modding platform (GPL-3.0). FFNx continues [FF7_OpenGL](https://github.com/Aali132/ff7_opengl) by
[Aali](http://forums.qhimm.com/index.php?topic=14922.0).

**FFNx core team** (as listed by the [FFNx project](https://github.com/julianxhokaxhiu/FFNx)):

- [Julian Xhokaxhiu](https://github.com/julianxhokaxhiu)
- [Tang-Tang Zhou](https://github.com/tangtang95)
- [Jérôme Arzel](https://github.com/myst6re)
- [CosmosXIII](https://github.com/CosmosXIII)

The Builder's Steam download follows [SteamKit2](https://github.com/SteamRE/SteamKit)'s protocol and
the Android port's use of [JavaSteam](https://github.com/Longi94/JavaSteam); its message definitions
come from [SteamDatabase/Protobufs](https://github.com/SteamDatabase/Protobufs). It unpacks Steam's
files with the [LZMA SDK](https://www.7-zip.org/sdk.html)'s decoder (public domain) and
[Zstandard](https://github.com/facebook/zstd)'s (BSD).

The static-recompilation core used here comes from
[FF7Recomp for Android](https://github.com/bhuiyah/ff7-recomp-android). Further FFNx contributors
and earlier Qhimm-era work are credited in [FFNx’s own README](https://github.com/julianxhokaxhiu/FFNx#credits).

---

## Legal

FF7Recomp for iOS is **GPL-3.0** ([`LICENSE`](LICENSE)), like FFNx and the Android port.

You need your own Steam copy of FINAL FANTASY VII. Builds that include the game are for your own
devices only and must not be distributed. Not affiliated with or endorsed by Square Enix.
FINAL FANTASY is a trademark of Square Enix. **Sideload only — not the App Store.**
