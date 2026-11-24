#!/usr/bin/env bash
# The kit FF7Recomp Builder (the Mac app, mac/builder) carries: everything the iOS app needs
# except the game, so the player's Mac only lifts, compiles and links their own ff7_en
# (mac/builder/build_ipa.py). It holds no game code and no game files, so it can be shared.
#
#   kit/VERSION                 what this kit is
#   kit/LIFT_VERSION            what the lift depends on (a new lifter means a new lift)
#   kit/lib/libff7_engine.a     the engine for iPhone without the lift (FF7_NO_GUEST): runtime,
#                               FF7 HLE, FFNx, bgfx/Metal, FFmpeg
#   kit/app/objects/*.o         the app's own code (SwiftUI launcher, Metal view, pad, ...)
#   kit/link.args               the app's link as Xcode does it, one argument per line, with
#                               @KIT@ @GUEST@ @OUT@ @SDK@ @TOOLCHAIN@ @SWIFTLIB@ @WORK@
#   kit/app/FF7RecompBundled.app  the app's resources and Info.plist, no executable
#   kit/compile.args            the lifted C's compile flags (@KIT@ @GEN@ @SDK@)
#   kit/include/                the headers the lifted C includes (pcrecomp's recomp32 runtime)
#   kit/lift/                   the lifter: run_lift.py, gen_extents.py, gen_retn_table.py,
#                               pcrecomp's tools, config/ (the catalog of the 1.02 exe)
#   kit/py/                     the lifter's Python modules (capstone, pefile)
#
#   bash tools/make_builder_kit.sh            # -> build-builder/kit
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
AND="$ROOT/external/ff7-recomp-android"
B="$ROOT/build-kit-ios"
DD="$ROOT/build-kit-dd"
KIT="$ROOT/build-builder/kit"

echo "== the engine for iPhone, without the game"
cmake -S "$ROOT" -B "$B" \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DFF7_BUNDLE_GAME=ON -DFF7_PLATFORM=ios -DFF7_BUILD_TESTS=OFF -DFF7_BASED_MEMORY=ON \
  -DFF7_NO_GUEST=ON \
  -DCMAKE_C_FLAGS="-ffile-prefix-map=$ROOT=." -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$ROOT=." \
  -DCMAKE_OBJC_FLAGS="-ffile-prefix-map=$ROOT=." -DCMAKE_OBJCXX_FLAGS="-ffile-prefix-map=$ROOT=." \
  >/dev/null   # the kit is shared: no paths of this Mac in it (see the check at the end)
cmake --build "$B" -j "$(sysctl -n hw.ncpu)" --target ff7_guest ff7_core ffnx >/dev/null
FF7_LINK_MODE=bundle FF7_BUILD_DIR="$B" bash "$ROOT/tools/darwin_link_metal_boot.sh" | tail -1
if ar t "$B/libff7_bundle.a" | grep -q '^recomp_'; then
  echo "the kit's engine holds lifted code: refusing" >&2; exit 1
fi

echo "== the app's own code and its link"
bash "$ROOT/tools/stage_ffnx_runtime.sh"
(cd "$ROOT/ios" && xcodegen generate >/dev/null)
LOG="$DD/build.log"
mkdir -p "$DD"
# The link fails here (no game yet): it is the compile and the link command that are wanted.
xcodebuild -project "$ROOT/ios/FF7Recomp.xcodeproj" -scheme FF7RecompBundled -sdk iphoneos \
  -configuration Release -destination generic/platform=iOS -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO FF7_CORE_DIR="$B" build >"$LOG" 2>&1 || true

rm -rf "$KIT"
mkdir -p "$KIT/lib" "$KIT/app/objects" "$KIT/include" "$KIT/lift/tools" "$KIT/lift/external/pcrecomp" "$KIT/py"
cp "$B/libff7_bundle.a" "$KIT/lib/libff7_engine.a"

python3 -I - "$LOG" "$KIT" "$B" "$DD" <<'PY'
import os, shlex, shutil, subprocess, sys
log, kit, b, dd = sys.argv[1:5]
lines = open(log, errors="replace").read().splitlines()
# Xcode prints "Ld <out> normal (in target ...)", then "    cd ...", then the command
cmd = None
for i, line in enumerate(lines):
    if line.startswith("Ld ") and "FF7RecompBundled.app/FF7RecompBundled" in line:
        for nxt in lines[i + 1:i + 6]:
            s = nxt.strip()
            if s.startswith("/") and "clang" in s.split()[0]:
                cmd = shlex.split(s)
                break
        break
if not cmd:
    sys.exit("no link command in the Xcode log: " + log)
sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()
toolchain = os.path.dirname(os.path.dirname(os.path.dirname(cmd[0])))     # .../XcodeDefault.xctoolchain
args, skip, objlist = [], 0, None
drop_pairs = {"-add_ast_path", "-dependency_info", "-object_path_lto", "-final_output"}
it = cmd[1:]
i = 0
while i < len(it):
    a = it[i]
    if a == "-Xlinker" and i + 3 < len(it) and it[i + 1] in drop_pairs:
        i += 4 if it[i + 2] == "-Xlinker" else 3
        continue
    if a == "-filelist":
        objlist = it[i + 1]
        args += ["-filelist", "@WORK@/objects.list"]
        i += 2
        continue
    if a == "-o":
        args += ["-o", "@OUT@"]
        i += 2
        continue
    if a.endswith("/libff7_bundle.a"):
        args += ["@GUEST@", "@KIT@/lib/libff7_engine.a"]
        i += 1
        continue
    if (a.startswith("-L") or a.startswith("-F")) and dd in a:
        i += 1
        continue
    args.append(a)
    i += 1
out = []
for a in args:
    a = a.replace(sdk, "@SDK@").replace(toolchain + "/usr/lib/swift/iphoneos", "@SWIFTLIB@").replace(toolchain, "@TOOLCHAIN@")
    if dd in a or b in a:
        sys.exit("link argument still points at this Mac's build: " + a)
    out.append(a)
if "@GUEST@" not in out:
    sys.exit("the link has no libff7_bundle.a")
open(os.path.join(kit, "link.args"), "w").write("\n".join(out) + "\n")
n = 0
for o in open(objlist).read().split():
    shutil.copy2(o, os.path.join(kit, "app", "objects", f"{n:03d}_" + os.path.basename(o)))
    n += 1
print(f"link: {len(out)} arguments, {n} app objects")
PY

APP_BUILT="$DD/Build/Products/Release-iphoneos/FF7RecompBundled.app"
cp -R "$APP_BUILT" "$KIT/app/FF7RecompBundled.app"
rm -rf "$KIT/app/FF7RecompBundled.app/FF7RecompBundled" "$KIT/app/FF7RecompBundled.app/_CodeSignature"

echo "== the lifter and the lifted C's headers and flags"
cp "$AND"/tools/{run_lift.py,gen_extents.py,gen_retn_table.py} "$KIT/lift/tools/"
cp -R "$AND/external/pcrecomp/tools" "$KIT/lift/external/pcrecomp/tools"
cp -R "$AND/config" "$KIT/lift/config"
find "$KIT/lift" -name __pycache__ -prune -exec rm -rf {} +
SITE="$(python3 -c 'import capstone, os; print(os.path.dirname(os.path.dirname(capstone.__file__)))')"
cp -R "$SITE/capstone" "$SITE/ordlookup" "$SITE/pefile.py" "$KIT/py/"
find "$KIT/py" -name __pycache__ -prune -exec rm -rf {} +
mkdir -p "$KIT/include/recomp32"
cp "$AND"/external/pcrecomp/runtime/recomp32/*.h "$KIT/include/recomp32/"
cp "$AND/src/host/portable_guest.h" "$KIT/include/"
cat > "$KIT/compile.args" <<'ARGS'
-DFF7_BASED_MEMORY
-DRECOMP_STRICT_ICALL
-I@KIT@/include/recomp32
-I@GEN@
-std=gnu11
-arch
arm64
-isysroot
@SDK@
-miphoneos-version-min=17.0
-fPIC
-O1
-w
-fno-strict-aliasing
-ffp-contract=off
-include
@KIT@/include/portable_guest.h
ARGS

echo "== no debug info, no paths of this Mac"
strip -S "$KIT/lib/libff7_engine.a" 2>/dev/null
for o in "$KIT"/app/objects/*.o; do strip -S "$o"; done
LEAKS="$(grep -rlaF "$HOME" "$KIT" || true)"
if [[ -n "$LEAKS" ]]; then
  echo "the kit still holds paths under $HOME:" >&2; echo "$LEAKS" >&2; exit 1
fi

VERSION="$(cd "$KIT" && find . -type f ! -name VERSION ! -name LIFT_VERSION -print0 | sort -z | xargs -0 shasum | shasum | cut -c1-16)"
echo "$VERSION" > "$KIT/VERSION"
# what the lift depends on (the lifter and its modules): a kit with only new app or engine code
# keeps the player's lift (build_ipa.py)
(cd "$KIT" && find lift py -type f -print0 | sort -z | xargs -0 shasum | shasum | cut -c1-16) > "$KIT/LIFT_VERSION"
echo "kit $VERSION: $(du -sh "$KIT" | cut -f1) in $KIT"
