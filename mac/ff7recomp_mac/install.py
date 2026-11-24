"""Build the game for an iPhone and install it there: the iOS side of the Android launcher's
on-device build (GameBuild.java), which iOS cannot run on the phone.

    tools/ff7recomp-mac install                      # the one iPhone connected to this Mac
    tools/ff7recomp-mac install --device "My iPhone"
    tools/ff7recomp-mac install --simulator booted   # a simulator (development)

1. find the iPhone (and the Apple ID in Xcode to sign with)
2. only when the game is not lifted yet on this Mac: take ff7_en.exe (--exe, the FF7Recomp app's
   game files on the iPhone, or this Mac's Steam install) and check it is the 1.02 US build
3. lift it to C (once: the exe is always the same build, so the lift is too)
4. compile and link the game with the engine for iOS (tools/build_ios_core.sh)
5. build the app with the game in it (FF7RecompBundled, signed with your Apple ID's team)
6. install it on the iPhone, over FF7Recomp if it is there: same app, so the game files stay

The build contains your own lift: it is for your own devices only, never for distribution.
"""
from __future__ import annotations

import gzip
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

EXE_SHA1 = "ac306ae92615af75ff36bba6347c67ca1284151d"   # ff7/resources/ff7_1.02/ff7_en
BUNDLE_ID = "com.ff7recomp.ios"
EXE_IN_APP = "Library/Application Support/FF7Recomp/game/ff7_en.exe"

ROOT = Path(__file__).resolve().parents[2]
AND = ROOT / "external" / "ff7-recomp-android"
GENERATED = AND / "generated" / "recomp"


class InstallError(Exception):
    pass


@dataclass
class Target:
    kind: str           # "device" or "simulator"
    ident: str          # devicectl identifier or simulator UDID
    name: str


def step(n: int, text: str) -> None:
    print(f"\n[{n}/6] {text}", flush=True)


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, **kw)


def sha1(path: Path) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


# ---------------------------------------------------------------- the iPhone

def physical_devices() -> list[dict]:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "devices.json"
        run(["xcrun", "devicectl", "list", "devices", "--json-output", str(out)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        devices = json.loads(out.read_text())["result"]["devices"]
    return [d for d in devices if d.get("hardwareProperties", {}).get("reality") == "physical"
            and d.get("hardwareProperties", {}).get("platform") == "iOS"]


def pick_target(device: str | None, simulator: str | None) -> Target:
    if simulator:
        udid = simulator
        if simulator == "booted":
            out = run(["xcrun", "simctl", "list", "devices", "booted", "-j"], capture_output=True, text=True).stdout
            booted = [d for ds in json.loads(out)["devices"].values() for d in ds if d.get("state") == "Booted"]
            if len(booted) != 1:
                raise InstallError(f"{len(booted)} simulators are booted: name one with --simulator UDID")
            udid = booted[0]["udid"]
        return Target("simulator", udid, f"simulator {udid}")

    phones = physical_devices()
    if device:
        phones = [d for d in phones if device in (d["identifier"], d.get("hardwareProperties", {}).get("udid"),
                                                  d.get("deviceProperties", {}).get("name"))]
        if not phones:
            raise InstallError(f"no iPhone named {device!r} is known to this Mac (xcrun devicectl list devices)")
    paired = [d for d in phones if d.get("connectionProperties", {}).get("pairingState") == "paired"]
    if not paired:
        raise InstallError("no paired iPhone: connect it with a cable, unlock it and tap Trust, then run this again")
    if len(paired) > 1:
        names = ", ".join(d.get("deviceProperties", {}).get("name", d["identifier"]) for d in paired)
        raise InstallError(f"more than one iPhone is paired ({names}): pick one with --device NAME")
    d = paired[0]
    return Target("device", d["identifier"], d.get("deviceProperties", {}).get("name", d["identifier"]))


def fetch_exe(target: Target, dest: Path, bundle_id: str = BUNDLE_ID) -> None:
    """Copies ff7_en.exe out of the FF7Recomp app's game files on the target."""
    if target.kind == "simulator":
        try:
            data = run(["xcrun", "simctl", "get_app_container", target.ident, bundle_id, "data"],
                       capture_output=True, text=True).stdout.strip()
        except subprocess.CalledProcessError:
            raise InstallError("FF7Recomp is not installed on that simulator")
        src = Path(data) / EXE_IN_APP
        if not src.is_file():
            raise InstallError(NO_FILES)
        shutil.copyfile(src, dest)
        return
    r = subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", target.ident,
                        "--domain-type", "appDataContainer", "--domain-identifier", bundle_id,
                        "--source", EXE_IN_APP, "--destination", str(dest)],
                       capture_output=True, text=True)
    if r.returncode != 0 or not dest.is_file():
        detail = (r.stderr or r.stdout).strip().splitlines()[-1:] or [""]
        raise InstallError(NO_FILES + f"\n(devicectl: {detail[0]})")


NO_FILES = ("FF7Recomp on the iPhone has no game files yet. Install FF7Recomp, open Game files and use "
            "Download from Steam or Find my FF7 folder first; or give the exe with --exe.")


# ---------------------------------------------------------------- the build

def lift(exe: Path, again: bool) -> None:
    if (GENERATED / "lift_stats.json").is_file() and not again:
        print("the game is already lifted (it is the same for every copy of the 1.02 exe); --relift does it again")
        return
    analysis = AND / "analysis"
    analysis.mkdir(exist_ok=True)
    catalog = analysis / "catalog.json"
    if not catalog.is_file():
        catalog.write_bytes(gzip.decompress((AND / "config" / "catalog.json.gz").read_bytes()))
    py = [sys.executable, "-I"]
    run(py + [str(AND / "tools" / "run_lift.py"), "lift", str(exe), str(catalog), str(GENERATED)], cwd=AND)
    run(py + [str(AND / "tools" / "gen_extents.py"), str(GENERATED)], cwd=AND)
    run(py + [str(AND / "tools" / "gen_retn_table.py")], cwd=AND)


def xcode_team() -> str | None:
    """The team of the Apple ID signed in to Xcode (Settings > Accounts), if there is one."""
    try:
        out = run(["defaults", "export", "com.apple.dt.Xcode", "-"], capture_output=True).stdout
        teams = plistlib.loads(out).get("IDEProvisioningTeamByIdentifier", {})
    except (subprocess.CalledProcessError, plistlib.InvalidFileException):
        return None
    ids = sorted({t.get("teamID") for account in teams.values() for t in account if t.get("teamID")})
    return ids[0] if len(ids) == 1 else (ids[0] if ids else None)


@dataclass
class Profile:
    """A development provisioning profile and the certificate it names (--profile), for signing
    without an Apple ID in Xcode: the app takes the profile's app ID as its bundle ID."""
    path: Path
    team: str
    bundle_id: str
    entitlements: dict
    cert_sha1: str


# What the app needs of a profile's entitlements: who it is, and room for the game's memory
# (the 4 GB-aligned guest window, docs/P1_METAL.md).
WANTED_ENTITLEMENTS = ("get-task-allow", "com.apple.developer.kernel.extended-virtual-addressing",
                       "com.apple.developer.kernel.increased-memory-limit")


def load_profile(path: Path) -> Profile:
    path = path.expanduser()
    try:
        data = run(["security", "cms", "-D", "-i", str(path)], capture_output=True).stdout
        info = plistlib.loads(data)
    except (subprocess.CalledProcessError, plistlib.InvalidFileException):
        raise InstallError(f"{path} is not a provisioning profile")
    team = info["TeamIdentifier"][0]
    app_id = info["Entitlements"]["application-identifier"]
    bundle = app_id.split(".", 1)[1]
    if "*" in bundle:
        bundle = bundle.replace("*", "com.ff7recomp.ios")
    cert = hashlib.sha1(info["DeveloperCertificates"][0]).hexdigest().upper()
    return Profile(path, team, bundle, info["Entitlements"], cert)


def keychain_has(sha1_hex: str) -> bool:
    out = run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True).stdout
    return sha1_hex.upper() in out.upper()


def sign_app(app: Path, profile: Profile) -> None:
    """Signs the app with the profile's certificate (from the keychain), as Xcode would."""
    shutil.copyfile(profile.path, app / "embedded.mobileprovision")
    ents = {"application-identifier": f"{profile.team}.{profile.bundle_id}",
            "com.apple.developer.team-identifier": profile.team,
            "keychain-access-groups": [f"{profile.team}.{profile.bundle_id}"]}
    for key in WANTED_ENTITLEMENTS:
        if profile.entitlements.get(key):
            ents[key] = profile.entitlements[key]
    with tempfile.NamedTemporaryFile("wb", suffix=".plist", delete=False) as f:
        plistlib.dump(ents, f)
        ent_path = f.name
    try:
        nested = sorted(list(app.rglob("*.dylib")) + list((app / "Frameworks").glob("*.framework")), reverse=True)
        for item in nested:
            run(["codesign", "--force", "--sign", profile.cert_sha1, "--timestamp=none", str(item)])
        run(["codesign", "--force", "--sign", profile.cert_sha1, "--timestamp=none",
             "--entitlements", ent_path, "--generate-entitlement-der", str(app)])
        run(["codesign", "--verify", "--strict", str(app)])
    finally:
        os.unlink(ent_path)
    print(f"signed as {profile.team}.{profile.bundle_id} with {', '.join(k.rsplit('.', 1)[-1] for k in ents if k in WANTED_ENTITLEMENTS)}")


def build_app(target: Target, team: str | None, profile: Profile | None = None) -> Path:
    kind = "device" if target.kind == "device" else "simulator"
    sdk = "iphoneos" if kind == "device" else "iphonesimulator"
    step(4, "Compiling the game and the engine for iOS (the first time takes a while)")
    run(["bash", str(ROOT / "tools" / "build_ios_core.sh"), kind])
    step(5, "Building the app with the game in it")
    run(["bash", str(ROOT / "tools" / "stage_ffnx_runtime.sh")])
    run(["xcodegen", "generate"], cwd=ROOT / "ios", stdout=subprocess.DEVNULL)
    derived = ROOT / "build-ios-dd"
    cmd = ["xcodebuild", "-project", str(ROOT / "ios" / "FF7Recomp.xcodeproj"), "-scheme", "FF7RecompBundled", "-sdk", sdk, "-configuration", "Release",
           "-destination", f"generic/platform=iOS{' Simulator' if kind == 'simulator' else ''}",
           "-derivedDataPath", str(derived), "-quiet", "build"]
    if kind == "device" and profile:
        cmd += ["CODE_SIGNING_ALLOWED=NO", f"PRODUCT_BUNDLE_IDENTIFIER={profile.bundle_id}"]
    elif kind == "device":
        cmd += ["-allowProvisioningUpdates", f"DEVELOPMENT_TEAM={team}", "CODE_SIGN_STYLE=Automatic"]
    run(cmd)
    app = derived / "Build" / "Products" / f"Release-{sdk}" / "FF7RecompBundled.app"
    if not app.is_dir():
        raise InstallError(f"the build made no {app}")
    if kind == "device" and profile:
        sign_app(app, profile)
    return app


def install_app(target: Target, app: Path) -> None:
    if target.kind == "simulator":
        run(["xcrun", "simctl", "install", target.ident, str(app)])
    else:
        run(["xcrun", "devicectl", "device", "install", "app", "--device", target.ident, str(app)])


# ---------------------------------------------------------------- the command

def mac_steam_exe() -> Path | None:
    """This Mac's own Steam install of the game, if there is one."""
    p = (Path.home() / "Library/Application Support/Steam/steamapps/common/FINAL FANTASY VII Steam Edition"
         / "ff7/resources/ff7_1.02/ff7_en")
    return p if p.is_file() else None


def get_exe(target: Target, exe: Path | None, dest: Path, bundle_id: str = BUNDLE_ID) -> str:
    """ff7_en from --exe, the iPhone's game files or this Mac's Steam install; says which."""
    if exe:
        shutil.copyfile(exe.expanduser(), dest)
        return str(exe)
    try:
        fetch_exe(target, dest, bundle_id)
        return f"FF7Recomp on {target.name}"
    except InstallError as e:
        steam = mac_steam_exe()
        if not steam:
            raise e
        shutil.copyfile(steam, dest)
        return "this Mac's Steam install"


def install(device: str | None = None, simulator: str | None = None, exe: Path | None = None,
            team: str | None = None, relift: bool = False, profile_path: Path | None = None) -> int:
    try:
        step(1, "Finding the iPhone")
        target = pick_target(device, simulator)
        print(f"target: {target.name}")
        profile = load_profile(profile_path) if profile_path and target.kind == "device" else None
        team = team or (None if profile else xcode_team())
        if profile:
            if not keychain_has(profile.cert_sha1):
                raise InstallError(f"the certificate of {profile.path.name} is not in your keychain: double-click "
                                   "its .p12 file and enter the .p12's password, then run this again")
            print(f"signing with {profile.path.name}: app ID {profile.team}.{profile.bundle_id}")
        elif target.kind == "device" and not team:
            raise InstallError("Xcode has no Apple ID to sign with. Open Xcode > Settings > Accounts, add your "
                               "Apple ID, then run this again; or sign with a development profile and its "
                               "certificate (--profile FILE.mobileprovision).")
        bundle_id = profile.bundle_id if profile else BUNDLE_ID

        lifted = (GENERATED / "lift_stats.json").is_file() and not relift
        if lifted:
            step(2, "ff7_en.exe")
            print("already lifted on this Mac (the lift is the same for every copy of the 1.02 exe); "
                  "--relift lifts it again")
            step(3, "Lifting the game to C")
            print("done before")
        else:
            with tempfile.TemporaryDirectory() as tmp:
                local = Path(tmp) / "ff7_en.exe"
                step(2, "Getting ff7_en.exe and checking it is the 1.02 US build")
                where = get_exe(target, exe, local, bundle_id)
                got = sha1(local)
                if got != EXE_SHA1:
                    raise InstallError(f"ff7_en.exe from {where} has SHA-1 {got}, not the 1.02 US build ({EXE_SHA1}). "
                                       "Patched game files are not supported.")
                print(f"ff7_en.exe from {where}: 1.02 US")
                step(3, "Lifting the game to C")
                lift(local, relift)

        app = build_app(target, team, profile)

        step(6, f"Installing on {target.name}")
        install_app(target, app)
        print("\nDone. Open FF7Recomp on the iPhone: get the game files in Game files if it has none yet, "
              "then press Play.")
        return 0
    except InstallError as e:
        print(f"\nff7recomp-mac install: {e}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(f"\nff7recomp-mac install: {' '.join(map(str, e.cmd[:3]))}… failed (exit {e.returncode})", file=sys.stderr)
        return 1


# ---------------------------------------------------------------- an unsigned IPA

IPA_DIR = ROOT / "build-ios-ipa"


def build_ipa(exe: Path | None = None, relift: bool = False, out: Path | None = None) -> int:
    """An unsigned FF7Recomp.ipa with the game in it, to sign and install with your own tools
    (a development profile, AltStore, SideStore...). On the iPhone it asks for the game files,
    checks them and plays. It holds your own lift: for your own devices only, never share it."""
    try:
        step(1, "ff7_en.exe")
        if (GENERATED / "lift_stats.json").is_file() and not relift:
            print("already lifted on this Mac; --relift lifts it again")
        else:
            with tempfile.TemporaryDirectory() as tmp:
                local = Path(tmp) / "ff7_en.exe"
                src = exe.expanduser() if exe else mac_steam_exe()
                if not src:
                    raise InstallError("no ff7_en to lift: pass --exe .../ff7/resources/ff7_1.02/ff7_en")
                shutil.copyfile(src, local)
                step(2, "Checking it is the 1.02 US build")
                got = sha1(local)
                if got != EXE_SHA1:
                    raise InstallError(f"{src} has SHA-1 {got}, not the 1.02 US build ({EXE_SHA1})")
                step(3, "Lifting the game to C")
                lift(local, relift)

        step(4, "Compiling the game and the engine for iPhone (the first time takes a while)")
        run(["bash", str(ROOT / "tools" / "build_ios_core.sh"), "device"])
        step(5, "Building the app, unsigned")
        run(["bash", str(ROOT / "tools" / "stage_ffnx_runtime.sh")])
        run(["xcodegen", "generate"], cwd=ROOT / "ios", stdout=subprocess.DEVNULL)
        derived = ROOT / "build-ios-dd"
        run(["xcodebuild", "-project", str(ROOT / "ios" / "FF7Recomp.xcodeproj"), "-scheme", "FF7RecompBundled",
             "-sdk", "iphoneos", "-configuration", "Release", "-destination", "generic/platform=iOS",
             "-derivedDataPath", str(derived), "-quiet", "build",
             "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="])
        app = derived / "Build" / "Products" / "Release-iphoneos" / "FF7RecompBundled.app"
        if not app.is_dir():
            raise InstallError(f"the build made no {app}")

        step(6, "Packing the IPA")
        out = (out or IPA_DIR / "FF7Recomp.ipa").expanduser().resolve()
        out.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory() as tmp:
            payload = Path(tmp) / "Payload"
            payload.mkdir()
            shutil.copytree(app, payload / app.name, symlinks=True)
            if out.exists():
                out.unlink()
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(payload), str(out)])
        size = out.stat().st_size / 1e6
        print(f"\n{out} ({size:.0f} MB, unsigned)")
        print("Sign it and install it on your iPhone. On first launch FF7Recomp asks for the game files "
              "(Find my FF7 folder), confirms them, and Play starts the game.\n"
              "It contains the game built from your own ff7_en.exe: for your own devices only, never share it.")
        return 0
    except InstallError as e:
        print(f"\nff7recomp-mac ipa: {e}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(f"\nff7recomp-mac ipa: {' '.join(map(str, e.cmd[:3]))}… failed (exit {e.returncode})", file=sys.stderr)
        return 1
