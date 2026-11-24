#!/usr/bin/env python3
"""Build FF7Recomp.ipa from your own FINAL FANTASY VII: the Mac side of what the Android
launcher does on the phone (GameBuild.java), which iOS cannot do.

The kit (tools/make_builder_kit.sh) carries no game code: the engine already compiled for
iPhone without the game, the app's own compiled code and its link, the app's resources, and the
lifter. This lifts your ff7_en to C, compiles it with Xcode's clang, links it with the kit into
the app, puts your game files (ff7_en.exe and data/) in the app, and packs an unsigned IPA.

    python3 build_ipa.py --kit KIT --game "/path/FINAL FANTASY VII Steam Edition" --out FF7Recomp.ipa

Prints "STEP i/n text", "PROGRESS f" (0..1 of the whole build) and "ERROR text" lines for the
FF7Recomp Builder app. Needs Xcode (the iOS SDK). Runs on the Mac's own python3 (3.9).

The IPA holds the game built from your copy and your game's data: for your own devices only,
never share it.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import gzip
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

EXE_SHA1 = "ac306ae92615af75ff36bba6347c67ca1284151d"   # ff7/resources/ff7_1.02/ff7_en (1.02 US)
LANGS = ("en", "fr", "de", "es")
STEPS = [
    ("Checking Xcode and your game folder", 0.01),
    ("Lifting ff7_en to C", 0.10),
    ("Compiling the game for iPhone", 0.55),
    ("Linking the app", 0.07),
    ("Adding your game files", 0.12),
    ("Packing the IPA", 0.15),
]
WHICH = ("Pick the main FINAL FANTASY VII folder as Steam installs it today (\"FINAL FANTASY VII Steam "
         "Edition\", the one with ff7 inside), not ff7/workingdir. No patch or older version is needed; "
         "patched game files are not supported.")


class BuildError(Exception):
    pass


class Progress:
    def __init__(self) -> None:
        self.index = -1
        self.base = 0.0

    def step(self, i: int) -> None:
        if self.index >= 0:
            self.base += STEPS[self.index][1]
        self.index = i
        print(f"STEP {i + 1}/{len(STEPS)} {STEPS[i][0]}", flush=True)
        self.part(0)

    def part(self, f: float) -> None:
        print(f"PROGRESS {min(1.0, self.base + STEPS[self.index][1] * max(0.0, min(1.0, f))):.4f}", flush=True)


def log(text: str) -> None:
    print(text, flush=True)


def run(cmd: list, **kw) -> subprocess.CompletedProcess:
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True, **kw)
    if r.returncode != 0:
        tail = (r.stderr or r.stdout).strip().splitlines()[-8:]
        raise BuildError(f"{Path(str(cmd[0])).name} failed:\n" + "\n".join(tail))
    return r


def sha1(path: Path) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


# ---------------------------------------------------------------- 1. Xcode, the folder

def xcode() -> dict:
    try:
        sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"]).stdout.strip()
        clang = run(["xcrun", "--sdk", "iphoneos", "-f", "clang"]).stdout.strip()
        swiftc = run(["xcrun", "--sdk", "iphoneos", "-f", "swiftc"]).stdout.strip()
    except (BuildError, FileNotFoundError):
        raise BuildError("Xcode is needed to build for iPhone (its iOS SDK and compiler). Install Xcode from "
                         "the App Store, open it once, then build again.")
    toolchain = Path(swiftc).parent.parent
    return {"sdk": sdk, "clang": clang, "toolchain": str(toolchain),
            "swiftlib": str(toolchain / "lib" / "swift" / "iphoneos")}


def install_root(picked: Path) -> Path:
    def has(base: Path) -> bool:
        return (base / "ff7/resources/ff7_1.02/ff7_en").is_file() and (base / "ff7/workingdir/data/field").is_dir()
    if has(picked):
        return picked
    if picked.name.lower() == "ff7" and has(picked.parent):
        return picked.parent
    raise BuildError("That folder does not hold the game. " + WHICH)


# ---------------------------------------------------------------- 2. the lift

def lifter(kit: Path, script: str, args: list, env: dict) -> None:
    """Runs one of the kit's lifter scripts on this python3 with the kit's modules
    (capstone, pefile) and the lifter's own folder first on the path."""
    path = str(kit / "lift" / "tools" / script)
    boot = ("import runpy, sys; sys.path[:0] = list(%r); sys.argv = [%r] + %r; "
            "runpy.run_path(%r, run_name='__main__')") % ((str(kit / "py"), str(kit / "lift" / "tools")), path,
                                                          [str(a) for a in args], path)
    full = dict(os.environ, **env)
    r = subprocess.run([sys.executable, "-I", "-c", boot], capture_output=True, text=True, env=full,
                       cwd=str(kit / "lift"))
    if r.returncode != 0:
        tail = (r.stderr or r.stdout).strip().splitlines()[-8:]
        raise BuildError(f"the lift ({script}) failed:\n" + "\n".join(tail))


def lift(kit: Path, exe: Path, work: Path, prog: Progress) -> Path:
    gen = work / "gen"
    stamp = work / "lift.stamp"
    stamp_file = kit / "LIFT_VERSION" if (kit / "LIFT_VERSION").is_file() else kit / "VERSION"
    want = stamp_file.read_text().strip() + " " + EXE_SHA1
    if (gen / "lift_stats.json").is_file() and stamp.is_file() and stamp.read_text().strip() == want:
        log("already lifted (same kit, same exe)")
        return gen
    shutil.rmtree(gen, ignore_errors=True)
    gen.mkdir(parents=True)
    catalog = work / "catalog.json"
    catalog.write_bytes(gzip.decompress((kit / "lift" / "config" / "catalog.json.gz").read_bytes()))
    env = {"PCRECOMP": str(kit / "lift" / "external" / "pcrecomp"), "FF7_CATALOG": str(catalog),
           "FF7_EXE": str(exe), "FF7_RETN_OUT": str(gen / "recomp_retn.c")}
    lifter(kit, "run_lift.py", ["lift", exe, catalog, gen], env)
    prog.part(0.8)
    lifter(kit, "gen_extents.py", [gen], env)
    lifter(kit, "gen_retn_table.py", [], env)
    stamp.write_text(want)
    return gen


# ---------------------------------------------------------------- 3. compile, 4. link

def compile_game(kit: Path, gen: Path, work: Path, xc: dict, prog: Progress) -> Path:
    obj = work / "obj"
    obj.mkdir(exist_ok=True)
    flags = (kit / "compile.args").read_text().split("\n")
    flags = [f.replace("@KIT@", str(kit)).replace("@GEN@", str(gen)).replace("@SDK@", xc["sdk"])
             for f in flags if f.strip()]
    sources = sorted(gen.glob("recomp_*.c"))
    if not sources:
        raise BuildError("the lift wrote no C files")
    sources.sort(key=lambda p: -p.stat().st_size)          # the big ones first
    done = [0]

    def one(src: Path) -> None:
        out = obj / (src.name + ".o")
        if out.is_file() and out.stat().st_mtime >= src.stat().st_mtime:
            return
        part = out.with_suffix(".o.part")
        run([xc["clang"]] + flags + ["-o", part, "-c", src])
        part.replace(out)

    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        for f in concurrent.futures.as_completed([pool.submit(one, s) for s in sources]):
            f.result()
            done[0] += 1
            prog.part(done[0] / len(sources))
    lib = work / "libff7_guest.a"
    if lib.exists():
        lib.unlink()
    run(["libtool", "-static", "-no_warning_for_no_symbols", "-o", lib] + sorted(obj.glob("*.o")))
    return lib


def link(kit: Path, guest: Path, work: Path, xc: dict) -> Path:
    out = work / "FF7RecompBundled"
    args = [a for a in (kit / "link.args").read_text().split("\n") if a.strip()]
    subst = {"@KIT@": str(kit), "@GUEST@": str(guest), "@OUT@": str(out), "@SDK@": xc["sdk"],
             "@SWIFTLIB@": xc["swiftlib"], "@TOOLCHAIN@": xc["toolchain"], "@WORK@": str(work)}
    full = []
    for a in args:
        for k, v in subst.items():
            a = a.replace(k, v)
        full.append(a)
    (work / "objects.list").write_text("\n".join(str(p) for p in sorted((kit / "app" / "objects").glob("*.o"))) + "\n")
    run([xc["clang"]] + full)
    return out


# ---------------------------------------------------------------- 5. the app, 6. the IPA

def patch_window_bin(data: bytes) -> bytes | None:
    """The dialog font fix (tools/fix_font_widths.py): M, W, m, w 11 pixels wide, not 8."""
    import struct
    at = 0
    for _ in range(2):
        if at + 6 > len(data):
            return None
        at += 6 + struct.unpack_from("<H", data, at)[0]
    if at + 6 > len(data):
        return None
    csize = struct.unpack_from("<H", data, at)[0]
    if at + 6 + csize > len(data):
        return None
    widths = bytearray(gzip.decompress(data[at + 6:at + 6 + csize]))
    wide = (0x2D, 0x37, 0x4D, 0x57)
    if max(wide) >= len(widths):
        return None
    changed = False
    for c in wide:
        if widths[c] & 31 == 8:
            widths[c] = (widths[c] & 0xE0) | 11
            changed = True
    if not changed:
        return None
    packed = gzip.compress(bytes(widths), compresslevel=9, mtime=0)
    if len(packed) > 0xFFFF:
        return None
    return data[:at] + struct.pack("<H", len(packed)) + data[at + 2:at + 6] + packed + data[at + 6 + csize:]


def assemble(kit: Path, binary: Path, install: Path, work: Path, prog: Progress) -> Path:
    payload = work / "Payload"
    shutil.rmtree(payload, ignore_errors=True)
    payload.mkdir()
    app = payload / "FF7RecompBundled.app"
    run(["cp", "-R", kit / "app" / "FF7RecompBundled.app", app])
    shutil.copy2(binary, app / "FF7RecompBundled")
    os.chmod(app / "FF7RecompBundled", 0o755)
    game = app / "game"
    game.mkdir()
    shutil.copy2(install / "ff7/resources/ff7_1.02/ff7_en", game / "ff7_en.exe")
    src = install / "ff7/workingdir/data"
    (game / "data").mkdir()
    entries = sorted(src.iterdir())
    for i, entry in enumerate(entries):
        if entry.name.lower().startswith("lang-") and entry.name[5:].lower() not in LANGS:
            continue
        # cp -c clones on the same APFS volume (no extra space), copies otherwise
        run(["cp", "-cR", entry, game / "data" / entry.name])
        prog.part((i + 1) / len(entries))
    for lang in LANGS:
        wb = game / "data" / f"lang-{lang}" / "kernel" / "window.bin"
        if wb.is_file():
            fixed = patch_window_bin(wb.read_bytes())
            if fixed:
                wb.chmod(0o644)
                wb.write_bytes(fixed)
    return payload


def pack(payload: Path, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".ipa.part")
    if tmp.exists():
        tmp.unlink()
    # no extended attributes or AppleDouble "._" files: they would break the app's signature
    run(["xattr", "-cr", payload])
    run(["ditto", "-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--zlibCompressionLevel", "1",
         "--keepParent", payload, tmp])
    tmp.replace(out)


# ---------------------------------------------------------------- the build

def build(kit: Path, game: Path, out: Path, work: Path) -> None:
    prog = Progress()
    started = time.time()
    prog.step(0)
    xc = xcode()
    install = install_root(game.expanduser())
    got = sha1(install / "ff7/resources/ff7_1.02/ff7_en")
    if got != EXE_SHA1:
        raise BuildError(f"This folder's ff7_en (SHA-1 {got[:12]}…) is not the 1.02 US build FF7Recomp is made "
                         f"from. {WHICH}")
    log(f"game: {install}")
    log(f"Xcode iOS SDK: {xc['sdk']}")
    work.mkdir(parents=True, exist_ok=True)

    prog.step(1)
    gen = lift(kit, install / "ff7/resources/ff7_1.02/ff7_en", work, prog)
    prog.step(2)
    guest = compile_game(kit, gen, work, xc, prog)
    prog.step(3)
    binary = link(kit, guest, work, xc)
    prog.step(4)
    payload = assemble(kit, binary, install, work, prog)
    prog.step(5)
    pack(payload, out)
    shutil.rmtree(payload, ignore_errors=True)
    prog.part(1)
    log(f"DONE {out}")
    log(f"built in {int(time.time() - started) // 60} min {int(time.time() - started) % 60} s, "
        f"{out.stat().st_size / 1e9:.2f} GB")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--kit", type=Path, required=True)
    p.add_argument("--game", type=Path, required=True, help="the FINAL FANTASY VII Steam Edition folder")
    p.add_argument("--out", type=Path, required=True, help="the IPA to write")
    p.add_argument("--work", type=Path, help="build folder (default: a folder next to the IPA)")
    a = p.parse_args(argv)
    work = a.work or a.out.parent / ".ff7recomp-build"
    try:
        build(a.kit.resolve(), a.game, a.out.resolve(), work.resolve())
        return 0
    except BuildError as e:
        print(f"ERROR {e}", flush=True)
        return 1
    except Exception as e:      # keep the app informed whatever happens
        print(f"ERROR {type(e).__name__}: {e}", flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
