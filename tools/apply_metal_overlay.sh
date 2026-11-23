#!/usr/bin/env bash
# Patch the fetched Android core for Apple Metal (idempotent). external/ is gitignored.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export ROOT
if [ ! -f "$ROOT/external/ff7-recomp-android/cmake/bgfx.cmake" ]; then
  echo "missing Android cmake/bgfx.cmake — run tools/setup_android_core.sh" >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
import os

root = Path(os.environ["ROOT"])
and_root = root / "external" / "ff7-recomp-android"
bgfx = and_root / "cmake" / "bgfx.cmake"
display = and_root / "src" / "ffnx_bridge" / "ffnx_display.cpp"
marker = "FF7_IOS_METAL_OVERLAY"

text = bgfx.read_text()
if marker not in text:
    old = """target_compile_definitions(bgfx
  PUBLIC  BGFX_CONFIG_RENDERER_VULKAN=1
  PRIVATE BGFX_CONFIG_RENDERER_OPENGLES=31   # FF7Recomp: Settings > Renderer > OpenGL ES
          BGFX_CONFIG_RENDERER_OPENGL=0
          BGFX_CONFIG_PREFER_DISCRETE_GPU=0
          BGFX_CONFIG_DYNAMIC_INDEX_BUFFER_SIZE=${FF7_BGFX_DYNAMIC_INDEX_BUFFER_SIZE}
          BGFX_CONFIG_DYNAMIC_VERTEX_BUFFER_SIZE=${FF7_BGFX_DYNAMIC_VERTEX_BUFFER_SIZE}
          BGFX_CONFIG_MAX_RECT_CACHE=${FF7_BGFX_MAX_RECT_CACHE}
          # FFNx uses 10240; Adreno's vkResetDescriptorPool clears the whole pool every frame (a
          # quarter of a core at 10240 sets x 16 samplers). bgfx adds 1024-set chunks as needed.
          BGFX_CONFIG_RENDERER_VULKAN_DESCRIPTOR_SETS_PER_POOL=1024)
target_link_libraries(bgfx PUBLIC bimg_decode bimg bx)
target_compile_options(bgfx PRIVATE -w)
if(ANDROID)
  target_link_libraries(bgfx PUBLIC android log dl EGL GLESv3)   # GLESv3, EGL: the OpenGL ES renderer
else()
  target_link_libraries(bgfx PUBLIC dl pthread)
endif()"""
    new = f"""# {marker}
if(APPLE)
  target_compile_definitions(bgfx
    PUBLIC  BGFX_CONFIG_RENDERER_METAL=1
    PRIVATE BGFX_CONFIG_RENDERER_VULKAN=0
            BGFX_CONFIG_RENDERER_OPENGLES=0
            BGFX_CONFIG_RENDERER_OPENGL=0
            BGFX_CONFIG_PREFER_DISCRETE_GPU=0
            BGFX_CONFIG_DYNAMIC_INDEX_BUFFER_SIZE=${{FF7_BGFX_DYNAMIC_INDEX_BUFFER_SIZE}}
            BGFX_CONFIG_DYNAMIC_VERTEX_BUFFER_SIZE=${{FF7_BGFX_DYNAMIC_VERTEX_BUFFER_SIZE}}
            BGFX_CONFIG_MAX_RECT_CACHE=${{FF7_BGFX_MAX_RECT_CACHE}})
else()
  target_compile_definitions(bgfx
    PUBLIC  BGFX_CONFIG_RENDERER_VULKAN=1
    PRIVATE BGFX_CONFIG_RENDERER_OPENGLES=31
            BGFX_CONFIG_RENDERER_OPENGL=0
            BGFX_CONFIG_PREFER_DISCRETE_GPU=0
            BGFX_CONFIG_DYNAMIC_INDEX_BUFFER_SIZE=${{FF7_BGFX_DYNAMIC_INDEX_BUFFER_SIZE}}
            BGFX_CONFIG_DYNAMIC_VERTEX_BUFFER_SIZE=${{FF7_BGFX_DYNAMIC_VERTEX_BUFFER_SIZE}}
            BGFX_CONFIG_MAX_RECT_CACHE=${{FF7_BGFX_MAX_RECT_CACHE}}
            BGFX_CONFIG_RENDERER_VULKAN_DESCRIPTOR_SETS_PER_POOL=1024)
endif()
target_link_libraries(bgfx PUBLIC bimg_decode bimg bx)
target_compile_options(bgfx PRIVATE -w)
if(ANDROID)
  target_link_libraries(bgfx PUBLIC android log dl EGL GLESv3)
elseif(APPLE)
  find_library(FF7_METAL_FRAMEWORK Metal REQUIRED)
  find_library(FF7_QUARTZ_FRAMEWORK QuartzCore REQUIRED)
  find_library(FF7_FOUNDATION_FRAMEWORK Foundation REQUIRED)
  find_library(FF7_IOKIT_FRAMEWORK IOKit REQUIRED)
  target_link_libraries(bgfx PUBLIC
    ${{FF7_METAL_FRAMEWORK}} ${{FF7_QUARTZ_FRAMEWORK}}
    ${{FF7_FOUNDATION_FRAMEWORK}} ${{FF7_IOKIT_FRAMEWORK}})
  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    find_library(FF7_UIKIT_FRAMEWORK UIKit REQUIRED)
    target_link_libraries(bgfx PUBLIC ${{FF7_UIKIT_FRAMEWORK}})
  else()
    find_library(FF7_APPKIT_FRAMEWORK AppKit REQUIRED)
    target_link_libraries(bgfx PUBLIC ${{FF7_APPKIT_FRAMEWORK}})
  endif()
else()
  target_link_libraries(bgfx PUBLIC dl pthread)
endif()"""
    if old not in text:
        raise SystemExit("cmake/bgfx.cmake layout changed; update tools/apply_metal_overlay.sh")
    bgfx.write_text(text.replace(old, new, 1))
    print("patched cmake/bgfx.cmake for Metal")
else:
    print("cmake/bgfx.cmake already Metal-overlaid")

d = display.read_text()
if "RendererType::Metal" not in d:
    d2 = d.replace(
        "init.type = bgfx::RendererType::Vulkan;",
        "init.type = bgfx::RendererType::Metal;",
    )
    d2 = d2.replace(
        "[display] bgfx::init (Vulkan) failed",
        "[display] bgfx::init (Metal) failed",
    )
    if d2 == d:
        raise SystemExit("ffnx_display.cpp: could not switch Vulkan -> Metal")
    display.write_text(d2)
    print("patched ffnx_display.cpp for Metal")
else:
    print("ffnx_display.cpp already Metal")
PY


# bx: macOS has <malloc/malloc.h>, not <malloc.h>
BX_ALLOC="$ROOT/external/ff7-recomp-android/external/bx/src/allocator.cpp"
if [ -f "$BX_ALLOC" ] && ! grep -q 'malloc/malloc.h' "$BX_ALLOC"; then
  python3 - <<'PY2'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external/ff7-recomp-android/external/bx/src/allocator.cpp"
t = p.read_text()
old = "#include <malloc.h>\n"
new = "#if defined(__APPLE__)\n#\tinclude <malloc/malloc.h>\n#else\n#\tinclude <malloc.h>\n#endif\n"
if old in t:
    p.write_text(t.replace(old, new, 1))
    print("patched bx allocator.cpp for Apple")
PY2
fi

# Prefer -xobjective-c++ + CoreVideo (Metal amalgamated is ObjC++)
BGFX_CMAKE="$ROOT/external/ff7-recomp-android/cmake/bgfx.cmake"
if [ -f "$BGFX_CMAKE" ] && ! grep -q 'xobjective-c++' "$BGFX_CMAKE"; then
  python3 - <<'PY2'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external/ff7-recomp-android/cmake/bgfx.cmake"
t = p.read_text()
needle = """elseif(APPLE)
  find_library(FF7_METAL_FRAMEWORK Metal REQUIRED)
  find_library(FF7_QUARTZ_FRAMEWORK QuartzCore REQUIRED)
  find_library(FF7_FOUNDATION_FRAMEWORK Foundation REQUIRED)
  find_library(FF7_IOKIT_FRAMEWORK IOKit REQUIRED)
  target_link_libraries(bgfx PUBLIC
    ${FF7_METAL_FRAMEWORK} ${FF7_QUARTZ_FRAMEWORK}
    ${FF7_FOUNDATION_FRAMEWORK} ${FF7_IOKIT_FRAMEWORK})"""
insert = """elseif(APPLE)
  target_compile_options(bgfx PRIVATE "-xobjective-c++")
  find_library(FF7_METAL_FRAMEWORK Metal REQUIRED)
  find_library(FF7_QUARTZ_FRAMEWORK QuartzCore REQUIRED)
  find_library(FF7_FOUNDATION_FRAMEWORK Foundation REQUIRED)
  find_library(FF7_IOKIT_FRAMEWORK IOKit REQUIRED)
  find_library(FF7_COREVIDEO_FRAMEWORK CoreVideo REQUIRED)
  find_library(FF7_COREFOUNDATION_FRAMEWORK CoreFoundation REQUIRED)
  target_link_libraries(bgfx PUBLIC
    ${FF7_METAL_FRAMEWORK} ${FF7_QUARTZ_FRAMEWORK}
    ${FF7_FOUNDATION_FRAMEWORK} ${FF7_IOKIT_FRAMEWORK}
    ${FF7_COREVIDEO_FRAMEWORK} ${FF7_COREFOUNDATION_FRAMEWORK})"""
if needle in t:
    p.write_text(t.replace(needle, insert, 1))
    print("patched bgfx.cmake ObjC++/CoreVideo")
else:
    print("bgfx.cmake Apple block already customized")
PY2
fi

# highly_experimental ships Windows backslash includes; clang on macOS needs /.
HE="$ROOT/external/ff7-recomp-android/external/deps/highly_experimental"
if [ -d "$HE" ]; then
  find "$HE" -type f \( -name '*.c' -o -name '*.h' \) -print0 \
    | xargs -0 perl -pi -e 's/#include "highly_experimental\\/#include "highly_experimental\//g'
fi

# FF7_IOS_SRGB_BACKENDS: without FFmpeg, video/ntscj.cpp is not built, and empty stubs for
# Renderer::setPostprocessingBackend / setYUVMovieBackend leave FFNx's final blit offscreen
# (the CAMetalLayer never receives a frame). Build the real selectors from this repo instead.
python3 - <<'PY3'
from pathlib import Path
import os, re
root = Path(os.environ["ROOT"])
and_root = root / "external" / "ff7-recomp-android"
cm = and_root / "cmake" / "ffnx.cmake"
t = cm.read_text()
marker = "# FF7_IOS_SRGB_BACKENDS"
if marker not in t:
    t += f"""
{marker}
if(APPLE AND NOT FF7_HAVE_FFMPEG)
  target_sources(ffnx PRIVATE "{root}/src/ffnx_overlay/renderer_srgb_backends.cpp")
endif()
"""
    cm.write_text(t)
    print("patched ffnx.cmake: sRGB renderer backends")
else:
    print("ffnx.cmake already has sRGB renderer backends")
stubs = and_root / "src" / "ffnx_port" / "link_stubs.cpp"
if stubs.exists():
    s = stubs.read_text()
    s2 = re.sub(r'extern "C" void ffnx_stub_fn_apple_[23]\(void\)[^\n]*\n', "", s)
    if s2 != s:
        stubs.write_text(s2)
        print("link_stubs.cpp: removed empty Renderer backend stubs")
PY3

# FF7_IOS_QUICKBOOT_TITLE: FF7_QUICKBOOT=title skips the credits (Start) and stops on the title
# screen. Until FFmpeg is built for Darwin the intro movies are named stops and the credits
# never advance on their own, so this is how the P1 exit test reaches the title.
python3 - <<'PY4'
from pathlib import Path
import os
root = Path(os.environ["ROOT"])
qb = root / "external" / "ff7-recomp-android" / "src" / "ffnx_port" / "quickboot.cpp"
t = qb.read_text()
marker = "FF7_IOS_QUICKBOOT_TITLE"
if marker not in t:
    edits = [
        ('    if (!std::strncmp(buf, "newgame", 7)) return 0;\n',
         '    if (!std::strncmp(buf, "newgame", 7)) return 0;\n'
         '    if (!std::strncmp(buf, "title", 5)) return 3;   // ' + marker + ': stop on the title screen\n'),
        ('        if (g_target >= 0) ffnx_info("quickboot: %s\\n", g_target == 2 ? "resume the save state" : g_target ? "continue" : "new game");\n',
         '        if (g_target >= 0) ffnx_info("quickboot: %s\\n", g_target == 3 ? "title screen" : g_target == 2 ? "resume the save state" : g_target ? "continue" : "new game");\n'),
        ('    case MODE_MAIN_MENU: {\n',
         '    case MODE_MAIN_MENU: {\n'
         '        if (g_target == 3) { ff7_platform_pad_inject(0); finish("at the title screen"); break; }\n'),
    ]
    for old, new in edits:
        if old not in t:
            raise SystemExit("quickboot.cpp layout changed; update tools/apply_metal_overlay.sh")
        t = t.replace(old, new, 1)
    qb.write_text(t)
    print("patched quickboot.cpp: FF7_QUICKBOOT=title")
else:
    print("quickboot.cpp already has the title target")
PY4

# FF7_IOS_BASED_MEMORY: -DFF7_BASED_MEMORY=ON builds the lift and runtime without
# RECOMP_FLAT_MEMORY: every guest access is g_mem_base + va. Native arm64 (macOS and iOS) keeps
# a 4 GB PAGEZERO, so the flat low-address layout the Android/Rosetta builds use is impossible.
python3 - <<'PY5'
from pathlib import Path
import os
root = Path(os.environ["ROOT"])
cm = root / "external" / "ff7-recomp-android" / "cmake" / "ff7core.cmake"
t = cm.read_text()
marker = "# FF7_IOS_BASED_MEMORY"
old = "set(FF7_GUEST_DEFS RECOMP_FLAT_MEMORY RECOMP_STRICT_ICALL)\n"
if marker not in t:
    if old not in t:
        raise SystemExit("ff7core.cmake layout changed; update tools/apply_metal_overlay.sh")
    t = t.replace(old, old + f"""{marker}
option(FF7_BASED_MEMORY "Guest memory at g_mem_base + va (native arm64 Apple)" OFF)
if(FF7_BASED_MEMORY)
  list(REMOVE_ITEM FF7_GUEST_DEFS RECOMP_FLAT_MEMORY)
  list(APPEND FF7_GUEST_DEFS FF7_BASED_MEMORY)
endif()
""", 1)
    cm.write_text(t)
    print("patched ff7core.cmake: FF7_BASED_MEMORY option")
else:
    print("ff7core.cmake already has FF7_BASED_MEMORY")
PY5

# FF7_IOS_BASED_MEMORY (host side): guest -> host conversions go through G2H, so the shims,
# HLE and FFNx work with the guest at g_mem_base (native arm64). A no-op in flat builds.
python3 -I "$ROOT/tools/based_memory_port.py" "$ROOT/external/ff7-recomp-android" | tail -1
# The FFNx sites clang found with -Wint-to-pointer-cast / -Wformat (based_memory_port.py
# warnings|formats, run once on FFNx 0adf0b32), stored as a patch on top of the transform.
FFNX_DIR="$ROOT/external/ff7-recomp-android/external/FFNx"
BM_PATCH="$ROOT/patches/ffnx-based-memory.patch"
if (cd "$FFNX_DIR" && patch -p1 -R -f -s -V none --dry-run < "$BM_PATCH" >/dev/null 2>&1); then
  echo "ffnx-based-memory.patch already applied"
else
  (cd "$FFNX_DIR" && patch -p1 --forward -s -V none < "$BM_PATCH") && echo "applied ffnx-based-memory.patch"
fi

# FF7_IOS_DARWIN_PORT: the Darwin portability edits of the first P1 bring-up (thread ids,
# MAP_FIXED_NOREPLACE, stack bounds, silent DirectSound, Apple-mangled link stubs, the Metal
# renderer choice, NEON by target arch, ...), as patches on top of everything above. Generated
# as the difference between this script's result and the working Mac tree; core pinned in
# tools/fetch_android_core.sh.
apply_once() {   # dir patch
  if (cd "$1" && patch -p1 -R -f -s -V none --dry-run < "$2" >/dev/null 2>&1); then
    echo "$(basename "$2") already applied"
  else
    (cd "$1" && patch -p1 --forward -s -V none < "$2") && echo "applied $(basename "$2")"
  fi
}
AND_DIR="$ROOT/external/ff7-recomp-android"
apply_once "$AND_DIR"                    "$ROOT/patches/android-core-darwin.patch"
apply_once "$AND_DIR/external/pcrecomp"  "$ROOT/patches/pcrecomp-darwin.patch"
apply_once "$AND_DIR/external/FFNx"      "$ROOT/patches/ffnx-darwin.patch"

# FF7_IOS_AUDIO_OBJCXX: on iOS miniaudio includes AVFoundation (its audio session), which
# needs Objective-C++; compile SoLoud's miniaudio backend that way on Apple mobile targets.
python3 - <<'PY6'
from pathlib import Path
import os
root = Path(os.environ["ROOT"])
cm = root / "external" / "ff7-recomp-android" / "cmake" / "ffnx_audio.cmake"
t = cm.read_text()
marker = "# FF7_IOS_AUDIO_OBJCXX"
old = "target_compile_options(ffnx_soloud PRIVATE -w)\n"
if marker not in t:
    if old not in t:
        raise SystemExit("ffnx_audio.cmake layout changed; update tools/apply_metal_overlay.sh")
    t = t.replace(old, old + f"""{marker}
if(CMAKE_SYSTEM_NAME MATCHES "iOS|tvOS|visionOS")
  set_source_files_properties("${{SL}}/src/backend/miniaudio/soloud_miniaudio.cpp"
                              PROPERTIES COMPILE_OPTIONS "-xobjective-c++")
  target_link_libraries(ffnx_soloud PUBLIC "-framework AVFoundation" "-framework AudioToolbox")
endif()
""", 1)
    cm.write_text(t)
    print("patched ffnx_audio.cmake: miniaudio as Objective-C++ on iOS")
else:
    print("ffnx_audio.cmake already builds miniaudio as Objective-C++ on iOS")
PY6

# FF7_IOS_FFMPEG_STUBS: without FFmpeg, FFNx's movie player (video/movies.cpp) is not built but
# its callers are. Movies end on their first frame (src/ffnx_overlay/ffmpeg_movie_stubs.cpp), so
# the app links strictly instead of with -undefined dynamic_lookup.
python3 - <<'PY7'
from pathlib import Path
import os
root = Path(os.environ["ROOT"])
cm = root / "external" / "ff7-recomp-android" / "cmake" / "ffnx.cmake"
t = cm.read_text()
marker = "# FF7_IOS_FFMPEG_STUBS"
if marker not in t:
    t += f"""
{marker}
if(APPLE AND NOT FF7_HAVE_FFMPEG)
  target_sources(ffnx PRIVATE "{root}/src/ffnx_overlay/ffmpeg_movie_stubs.cpp")
endif()
"""
    cm.write_text(t)
    print("patched ffnx.cmake: FFmpeg movie stubs")
else:
    print("ffnx.cmake already has the FFmpeg movie stubs")
PY7
