#!/usr/bin/env bash
# Darwin link for ff7_metal_boot after:
#   cmake -S . -B build-metal-x64 -DFF7_BUNDLE_GAME=ON -DFF7_PLATFORM=mac \
#         -DCMAKE_OSX_ARCHITECTURES=x86_64 && cmake --build build-metal-x64
#
# Apple ld64 cannot --allow-multiple-definition (FFNx header globals). This script:
#   1) copies uniquely-pathed CMake objects (ar member names collide on macOS)
#   2) weakens extra definitions listed in tools/darwin_dup_syms.txt (now empty). FFNx's
#      header-defined globals are made C++17 `inline` at the source instead
#      (FF7_IOS_HEADER_INLINE in apply_metal_overlay.sh), which keeps one copy as
#      /FORCE:MULTIPLE and --allow-multiple-definition do. Do not localize duplicates: that gave
#      each object a private copy and split shared state (the field opcode table, positions, ...).
#      llvm-objcopy --weaken-symbol did not take effect on these Mach-O objects in testing.
#   3) links with -undefined dynamic_lookup + -pagezero_size (Rosetta x86_64)
#
# Native arm64 cannot shrink PAGEZERO (kernel SIGKILL); guest flat 32-bit VAs need
# Rosetta x86_64 until a non-flat memory model exists.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
B="${FF7_BUILD_DIR:-$ROOT/build-metal-x64}"
if [[ ! -f "$B/libffnx.a" && -f "$ROOT/build-metal/libffnx.a" ]]; then
  B="$ROOT/build-metal"
fi
test -f "$B/libffnx.a"
OBJCOPY="${OBJCOPY:-/opt/homebrew/opt/llvm/bin/llvm-objcopy}"
LLVM_AR="${LLVM_AR:-/opt/homebrew/opt/llvm/bin/llvm-ar}"
test -x "$OBJCOPY"
test -x "$LLVM_AR"

ARCH="$(lipo -archs "$B/libffnx.a" 2>/dev/null | awk '{print $1}')"
if [[ -z "$ARCH" ]]; then
  ARCH="$(file "$B/CMakeFiles/ffnx.dir"/*/*.o 2>/dev/null | head -1 | sed -n 's/.*architecture //p')"
fi
# Detect from a known object if needed
if [[ -z "$ARCH" ]]; then
  sample="$(find "$B/CMakeFiles/ffnx.dir" -name '*.o' | head -1)"
  ARCH="$(lipo -archs "$sample" 2>/dev/null || true)"
fi
echo "linking build dir=$B arch=${ARCH:-unknown}"

DUP_LIST="$B/dup_syms_mangled.txt"
# The curated list (FFNx header globals defined in several objects). The discovery fallback
# below over-collects (thousands of symbols) and hides real definitions.
if [[ ! -f "$DUP_LIST" && -f "$ROOT/tools/darwin_dup_syms.txt" ]]; then
  cp "$ROOT/tools/darwin_dup_syms.txt" "$DUP_LIST"
fi
if [[ ! -f "$DUP_LIST" ]]; then
  # Fallback: discover duplicates across CMake objects (STD globals only).
  python3 - <<PY
import collections, subprocess
from pathlib import Path
root = Path("$B/CMakeFiles/ffnx.dir")
defs = collections.defaultdict(list)
for o in sorted(root.rglob("*.o")):
    try:
        out = subprocess.check_output(["nm", "-gU", str(o)], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        continue
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] in "STD":
            defs[parts[-1]].append(o)
dups = sorted(s for s, os_ in defs.items() if len(os_) > 1)
Path("$DUP_LIST").write_text("\\n".join(dups) + ("\\n" if dups else ""))
print(f"wrote {len(dups)} duplicate symbols to $DUP_LIST")
PY
fi

OUT="$B/ffnx_dedup"
rm -rf "$OUT" && mkdir -p "$OUT/objs"

python3 - <<PY
import collections, shutil, subprocess
from pathlib import Path

objcopy = "$OBJCOPY"
src_root = Path("$B/CMakeFiles/ffnx.dir")
out = Path("$OUT/objs")
syms = [s for s in Path("$DUP_LIST").read_text().splitlines() if s]

copied = []
for o in sorted(src_root.rglob("*.o")):
    rel = o.relative_to(src_root).as_posix().replace("/", "__")
    dest = out / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(o, dest)
    copied.append(dest)

opsf_root = Path("$B/CMakeFiles/ffnx_openpsf.dir")
if opsf_root.is_dir():
    for o in sorted(opsf_root.rglob("*.o")):
        dest = out / ("openpsf__" + o.name)
        shutil.copy2(o, dest)
        copied.append(dest)

defs = collections.defaultdict(list)
for o in copied:
    try:
        nm = subprocess.check_output(["nm", "-gU", str(o)], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        continue
    have = {line.split()[-1] for line in nm.splitlines()
            if len(line.split()) >= 3 and line.split()[1] in "STD"}
    for s in syms:
        if s in have:
            defs[s].append(o)

for s in syms:
    owners = defs.get(s, [])
    for o in owners[1:]:
        subprocess.check_call([objcopy, f"--weaken-symbol={s}", str(o)])
print(f"weakened extras for {len(syms)} symbols across {len(copied)} objects")
PY

"$LLVM_AR" rcs "$OUT/libffnx_dedup.a" "$OUT"/objs/*.o

# Seek/FFmpeg named-stops live in ffnx_port/link_stubs.cpp already — do not redefine them.

CC_ARCH=()
LINK_EXTRA=()
if [[ "${ARCH}" == *x86_64* ]] || [[ "${ARCH}" == i386 ]]; then
  CC_ARCH=(-arch x86_64)
  # Small PAGEZERO frees low 4GB for guest MAP_FIXED (Rosetta only). Host must not
  # land on PE/arena: disable PIE and park the image above 4GB.
  LINK_EXTRA+=(
    -Xlinker -pagezero_size -Xlinker 0x1000
    -Xlinker -no_pie
    -Xlinker -image_base -Xlinker 0x100000000
    # Pin a zero-fill segment over the PE image VA (ff7_guest_reserve.s) so Rosetta and
    # dyld never load images there before pe_loader's MAP_FIXED.
    -Xlinker -segaddr -Xlinker __FF7GUEST -Xlinker 0x400000
    -Xlinker -segprot -Xlinker __FF7GUEST -Xlinker rw -Xlinker rw
  )
  RESERVE_O="$B/CMakeFiles/ff7_metal_boot.dir/src/mac/ff7_guest_reserve.s.o"
  mkdir -p "$(dirname "$RESERVE_O")"
  clang "${CC_ARCH[@]}" -c "$ROOT/src/mac/ff7_guest_reserve.s" -o "$RESERVE_O"
  LINK_EXTRA+=("$RESERVE_O" -Wl,-u,_ff7_guest_image_reserve)
elif [[ "${ARCH}" == *arm64* ]]; then
  # Native arm64 keeps the 4 GB PAGEZERO; the core must be built with -DFF7_BASED_MEMORY=ON
  # (guest window at g_mem_base, tools/based_memory_port.py).
  CC_ARCH=(-arch arm64)
fi

# The core and everything under it, in link order (libff7_platform is the host's own).
CORE_LIBS=(
  "$B/libff7_core.a" "$OUT/libffnx_dedup.a"
  "$B/libbgfx.a" "$B/libbimg_decode.a" "$B/libbimg.a" "$B/libbx.a" "$B/libastcenc.a"
  "$B/libffnx_png.a" "$B/libffnx_imgui.a" "$B/libffnx_pugixml.a" "$B/libffnx_xxhash.a"
  "$B/libffnx_soloud.a" "$B/libffnx_vgmstream.a" "$B/libffnx_lz4.a"
  "$B/libffnx_ogg.a" "$B/libffnx_vorbis.a" "$B/libff7_rcheevos.a" "$B/libffnx-resources.a"
)

# FF7_LINK_MODE=bundle: merge the core into one static library for an app to link
# (the iOS app: ios/project.yml), instead of linking ff7_metal_boot.
if [[ "${FF7_LINK_MODE:-exe}" == bundle ]]; then
  rm -f "$B/libff7_bundle.a"
  libtool -static -no_warning_for_no_symbols -o "$B/libff7_bundle.a" "${CORE_LIBS[@]}"
  echo "bundled $B/libff7_bundle.a ($(du -h "$B/libff7_bundle.a" | cut -f1))"
  exit 0
fi

# Ensure Mac Metal window object exists (ObjC++).
MAC_WIN_O="$B/CMakeFiles/ff7_metal_boot.dir/src/mac/ff7_mac_metal_window.mm.o"
if [[ ! -f "$MAC_WIN_O" ]]; then
  mkdir -p "$(dirname "$MAC_WIN_O")"
  clang++ "${CC_ARCH[@]}" -c -O2 -fobjc-arc \
    -I"$ROOT/src/mac" -I"$ROOT/src/platform" -I"$ROOT/src/ios" \
    "$ROOT/src/mac/ff7_mac_metal_window.mm" -o "$MAC_WIN_O"
fi
# Refresh boot .c if needed
BOOT_O="$B/CMakeFiles/ff7_metal_boot.dir/tools/ff7_metal_boot.c.o"
clang "${CC_ARCH[@]}" -c -O2 \
  -I"$ROOT/src/mac" -I"$ROOT/src/platform" -I"$ROOT/src/ios" \
  -DFF7_BUNDLE_GAME=1 -DFF7_PLATFORM_mac=1 \
  "$ROOT/tools/ff7_metal_boot.c" -o "$BOOT_O"

clang++ "${CC_ARCH[@]}" -o "$B/ff7_metal_boot" \
  "$BOOT_O" "$MAC_WIN_O" \
  "$B/libff7_platform.a" "${CORE_LIBS[@]}" \
  -framework Metal -framework QuartzCore -framework Foundation -framework IOKit \
  -framework AppKit -framework CoreVideo -framework CoreFoundation \
  -framework CoreMedia -framework VideoToolbox -framework AudioToolbox \
  -Wl,-u,_ff7_boot_and_run -Wl,-undefined,dynamic_lookup \
  ${LINK_EXTRA[@]+"${LINK_EXTRA[@]}"} \
  -lc++ -lz -lpthread

codesign -s - --force "$B/ff7_metal_boot" >/dev/null
echo "linked $B/ff7_metal_boot"
file "$B/ff7_metal_boot"
nm "$B/ff7_metal_boot" | grep ff7_boot_and_run || true
