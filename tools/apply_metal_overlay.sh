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
# FF7_IOS_SURFACE_RESIZE: follow the app's surface when it changes size while the game runs
# (iPhone Duo folding and unfolding, iPad split screen and Stage Manager). FFNx sized its
# swapchain once at boot; on Windows a WM_SIZE message resets the renderer, and this does the
# same from the render thread, once per frame, when ff7_platform_window() reports a new size.
# ffnx-darwin.patch rewrites renderer.cpp whole, so the block is taken out while that patch's
# "already applied" check runs and put back after it.
ff7_surface_resize() {   # apply|undo
python3 - "$1" <<'PY13'
from pathlib import Path
import os, sys
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-android" / "external" / "FFNx" / "src" / "renderer.cpp"
t = p.read_text()
marker = "FF7_IOS_SURFACE_RESIZE"
old = "    bgfx::frame(frameFlags);\n"
new = (old +
       "#if defined(FFNX_ANDROID) && defined(__APPLE__)\n"
       "    {   // FF7_IOS_SURFACE_RESIZE: the app's surface changed size (fold, split screen)\n"
       "        int w = 0, h = 0;\n"
       "        ff7_platform_window(&w, &h);\n"
       "        if (w > 0 && h > 0 && (w != (int)window_size_x || h != (int)window_size_y)) {\n"
       "            window_size_x = w;\n"
       "            window_size_y = h;\n"
       "            reset();\n"
       "        }\n"
       "    }\n"
       "#endif\n")
if sys.argv[1] == "undo":
    if marker in t:
        p.write_text(t.replace(new, old, 1))
    raise SystemExit(0)
if marker not in t:
    if t.count(old) != 1:
        raise SystemExit("renderer.cpp layout changed; update FF7_IOS_SURFACE_RESIZE in tools/apply_metal_overlay.sh")
    p.write_text(t.replace(old, new, 1))
    print("patched renderer.cpp: FF7_IOS_SURFACE_RESIZE")
else:
    print("renderer.cpp already has FF7_IOS_SURFACE_RESIZE")
PY13
}

AND_DIR="$ROOT/external/ff7-recomp-android"
ff7_surface_resize undo
apply_once "$AND_DIR"                    "$ROOT/patches/android-core-darwin.patch"
apply_once "$AND_DIR/external/pcrecomp"  "$ROOT/patches/pcrecomp-darwin.patch"
apply_once "$AND_DIR/external/FFNx"      "$ROOT/patches/ffnx-darwin.patch"
ff7_surface_resize apply

# FF7_IOS_PAD_FRAME: tell the platform layer each game frame, so a tap shorter than a frame
# still reaches the game (ff7_platform_pad_frame in src/platform/ff7_platform.c).
python3 - <<'PY14'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-android" / "src" / "ffnx_port" / "companion.cpp"
t = p.read_text()
marker = "FF7_IOS_PAD_FRAME"
old = 'extern "C" void ff7_companion_frame() {\n'
new = ('extern "C" void ff7_platform_pad_frame(void) __attribute__((weak));   // FF7_IOS_PAD_FRAME\n'
       + old +
       "    if (ff7_platform_pad_frame) ff7_platform_pad_frame();\n")
if marker in t:
    print("companion.cpp already has FF7_IOS_PAD_FRAME")
else:
    if t.count(old) != 1:
        raise SystemExit("companion.cpp layout changed; update FF7_IOS_PAD_FRAME in tools/apply_metal_overlay.sh")
    p.write_text(t.replace(old, new, 1))
    print("patched companion.cpp: FF7_IOS_PAD_FRAME")
PY14

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

# FF7_IOS_HEADER_INLINE: FFNx defines some globals and functions in headers (each including file
# gets a copy). Windows (/FORCE:MULTIPLE) and Android (--allow-multiple-definition) bind every
# reference to one copy; ld64 has no such flag. Mark them C++17 `inline`, so the toolchain keeps
# exactly one: without it FFNx's field opcode table, field positions, widescreen sizes, movie
# timing and input listeners were split per source file (a new game's first field looped on
# "original opcode table empty").
python3 - <<'PY8'
from pathlib import Path
import os
root = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-android" / "external"
EDITS = [
    ("FFNx/src/input.h", "std::vector<MouseListener*> mouseListeners;", "inline std::vector<MouseListener*> mouseListeners;"),
    ("FFNx/src/input.h", "std::vector<KeyListener*> keyListeners;", "inline std::vector<KeyListener*> keyListeners;"),
    ("FFNx/src/widescreen.h", "int wide_game_x = 0;", "inline int wide_game_x = 0;"),
    ("FFNx/src/widescreen.h", "int wide_game_y = 0;", "inline int wide_game_y = 0;"),
    ("FFNx/src/widescreen.h", "int wide_game_width = 854;", "inline int wide_game_width = 854;"),
    ("FFNx/src/widescreen.h", "int wide_game_height = 480;", "inline int wide_game_height = 480;"),
    ("FFNx/src/ff7/world/utils.h", "bool is_key_pressed(int current_key_status, int key)", "inline bool is_key_pressed(int current_key_status, int key)"),
    ("FFNx/src/ff7/world/utils.h", "bool is_key_pressed_first_time(int current_key_status, int prev_key_status, int key)", "inline bool is_key_pressed_first_time(int current_key_status, int prev_key_status, int key)"),
    ("FFNx/src/ff7/world/utils.h", "bool is_key_released(int current_key_status, int prev_key_status, int key)", "inline bool is_key_released(int current_key_status, int prev_key_status, int key)"),
    ("FFNx/src/ff7/field/background.h", "    vector2<float>\n        field_curr_delta_world_pos,", "    inline vector2<float>\n        field_curr_delta_world_pos,"),
    ("FFNx/src/ff7/field/model.h", "std::array<external_field_model_data, MAX_FIELD_MODELS> external_model_data;", "inline std::array<external_field_model_data, MAX_FIELD_MODELS> external_model_data;"),
    ("FFNx/src/ff7/field/model.h", "uint32_t ff7_kawai_current_model_id = 0xFF;", "inline uint32_t ff7_kawai_current_model_id = 0xFF;"),
    ("FFNx/src/ff7/field/opcode.h", "std::array<uint32_t, 256> original_opcode_table {0};", "inline std::array<uint32_t, 256> original_opcode_table {0};"),
    ("FFNx/src/movies.h", "extern short movie_fps_ratio = 1;", "inline short movie_fps_ratio = 1;"),
    ("FFNx/src/movies.h", "extern bool is_movie_bgfield = false;", "inline bool is_movie_bgfield = false;"),
    ("FFNx/src/ff8/file.h", "uint32_t(*ff8_read_file)(uint32_t count, void* buffer, struct ff8_file* file);", "inline uint32_t(*ff8_read_file)(uint32_t count, void* buffer, struct ff8_file* file);"),
    ("FFNx/src/ff8/file.h", "void (*ff8_close_file)(struct ff8_file* file);", "inline void (*ff8_close_file)(struct ff8_file* file);"),
    ("deps/openpsf/include/openpsf/openpsf.h", "PsfFlags operator|(PsfFlags flags, PsfFlags other) noexcept {", "inline PsfFlags operator|(PsfFlags flags, PsfFlags other) noexcept {"),
]
n = 0
for rel, old, new in EDITS:
    p = root / rel
    raw = p.read_bytes().decode("utf-8", "surrogateescape")
    crlf = "\r\n" in raw
    t = raw.replace("\r\n", "\n")
    if new in t:
        continue
    if t.count(old) != 1:
        raise SystemExit(f"{rel}: layout changed; update FF7_IOS_HEADER_INLINE in tools/apply_metal_overlay.sh")
    t = t.replace(old, new, 1)
    p.write_bytes((t.replace("\n", "\r\n") if crlf else t).encode("utf-8", "surrogateescape"))
    n += 1
print(f"header definitions made inline: {n}" if n else "header definitions already inline")
PY8

# FF7_IOS_DSOUND_COREAUDIO: the DirectSound HLE mixer (src/hle/ff7_dsound.c) plays the game's
# sound effects through AAudio on Android. On Apple, android-core-darwin.patch splits its mix loop
# into mix_frames() (the AAudio callback calls it unchanged) and has mixer_start() open a CoreAudio
# output unit, src/hle_overlay/ff7_dsound_coreaudio.c, built into ff7_core here. If no output can
# be opened the mixer stays silent and the game runs on.
python3 - <<'PY9'
from pathlib import Path
import os
root = Path(os.environ["ROOT"])
cm = root / "external" / "ff7-recomp-android" / "cmake" / "ff7core.cmake"
t = cm.read_text()
marker = "# FF7_IOS_DSOUND_COREAUDIO"
old = "if(ANDROID)\n  target_link_libraries(ff7_core PUBLIC aaudio)    # ff7_dsound.c mixer\nendif()\n"
if marker not in t:
    if t.count(old) != 1:
        raise SystemExit("ff7core.cmake layout changed; update FF7_IOS_DSOUND_COREAUDIO in tools/apply_metal_overlay.sh")
    t = t.replace(old, old + f"""{marker}: the mixer's CoreAudio output on Apple (this repo's src/hle_overlay)
if(APPLE)
  target_sources(ff7_core PRIVATE "{root}/src/hle_overlay/ff7_dsound_coreaudio.c")
  target_link_libraries(ff7_core PUBLIC "-framework AudioToolbox")
endif()
""", 1)
    cm.write_text(t)
    print("patched ff7core.cmake: CoreAudio mixer source on Apple")
else:
    print("ff7core.cmake already builds the CoreAudio mixer")
PY9

# FF7_IOS_FFMPEG_APPLE: on Apple, FFNx's FFmpeg comes from tools/build_ffmpeg_apple.sh
# (build/ffmpeg-apple-<target> in the Android tree). When that target's libraries exist, FFNx
# builds its real movie player (video/movies.cpp, video/ntscj.cpp) and the stubs above drop out;
# otherwise nothing changes. -DFF7_FFMPEG_DIR=... overrides the folder.
python3 - <<'PY10'
from pathlib import Path
import os
root = Path(os.environ["ROOT"])
cm = root / "external" / "ff7-recomp-android" / "cmake" / "ffnx.cmake"
t = cm.read_text()
marker = "# FF7_IOS_FFMPEG_APPLE"
old = 'set(FF7_FFMPEG_DIR "${FF7_ROOT}/build/ffmpeg-android")\n'
if marker not in t:
    if t.count(old) != 1:
        raise SystemExit("ffnx.cmake layout changed; update FF7_IOS_FFMPEG_APPLE in tools/apply_metal_overlay.sh")
    t = t.replace(old, f"""{marker}: tools/build_ffmpeg_apple.sh (ff7-recomp-ios)
if(APPLE AND NOT FF7_FFMPEG_DIR)
  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
      set(FF7_FFMPEG_DIR "${{FF7_ROOT}}/build/ffmpeg-apple-ios-simulator")
    else()
      set(FF7_FFMPEG_DIR "${{FF7_ROOT}}/build/ffmpeg-apple-ios-device")
    endif()
  elseif(CMAKE_OSX_ARCHITECTURES MATCHES "x86_64")
    set(FF7_FFMPEG_DIR "${{FF7_ROOT}}/build/ffmpeg-apple-macos-x86_64")
  else()
    set(FF7_FFMPEG_DIR "${{FF7_ROOT}}/build/ffmpeg-apple-macos-arm64")
  endif()
endif()
if(NOT FF7_FFMPEG_DIR)
{old}endif()
""", 1)
    cm.write_text(t)
    print("patched ffnx.cmake: FFmpeg from tools/build_ffmpeg_apple.sh on Apple")
else:
    print("ffnx.cmake already looks for tools/build_ffmpeg_apple.sh's FFmpeg")
# The FFmpeg folder in use, for tools/darwin_link_metal_boot.sh (empty file: no FFmpeg).
marker2 = "# FF7_IOS_FFMPEG_DIR_FILE"
t = cm.read_text()
if marker2 not in t:
    t += f"""
{marker2}: tells tools/darwin_link_metal_boot.sh which FFmpeg libraries to link
if(APPLE)
  if(FF7_HAVE_FFMPEG)
    file(WRITE "${{CMAKE_BINARY_DIR}}/ff7_ffmpeg_dir.txt" "${{FF7_FFMPEG_DIR}}")
  else()
    file(WRITE "${{CMAKE_BINARY_DIR}}/ff7_ffmpeg_dir.txt" "")
  endif()
endif()
"""
    cm.write_text(t)
    print("patched ffnx.cmake: records the FFmpeg folder for the Apple link")
PY10

# FF7_IOS_QUICKBOOT_KEEP_FMV: FF7_QUICKBOOT=newgame skips the opening movie. With
# FF7_QUICKBOOT_KEEP_FMV=1 it lets it play (checking FFmpeg movies: tools/build_ffmpeg_apple.sh).
python3 - <<'PY11'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-android" / "src" / "ffnx_port" / "quickboot.cpp"
t = p.read_text()
marker = "FF7_QUICKBOOT_KEEP_FMV"
old = "        if (ff7_externals.movie_object && ff7_externals.movie_object->is_playing) {\n"
if marker not in t:
    if t.count(old) != 1:
        raise SystemExit("quickboot.cpp layout changed; update FF7_IOS_QUICKBOOT_KEEP_FMV in tools/apply_metal_overlay.sh")
    t = t.replace(old, "        if (ff7_externals.movie_object && ff7_externals.movie_object->is_playing\n"
                       f"            && !std::getenv(\"{marker}\")) {{   // FF7_IOS_QUICKBOOT_KEEP_FMV\n", 1)
    p.write_text(t)
    print("patched quickboot.cpp: FF7_QUICKBOOT_KEEP_FMV")
else:
    print("quickboot.cpp already has FF7_QUICKBOOT_KEEP_FMV")
PY11

# FF7_IOS_DARWIN_HAND_EDITS: two Darwin edits made by hand during bring-up that no step above
# reproduced (found by replaying external/ from pristine): pcrecomp's guest arena maps with
# MAP_FIXED_NOREPLACE / MAP_NORESERVE, which Darwin lacks, and openpsf keeps string literals
# in a `char *` (an error in C++11 and later).
python3 - <<'PY12'
from pathlib import Path
import os
ext = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-android" / "external"
EDITS = [
    ("pcrecomp/runtime/win32hle/guest_alloc.c",
     "#ifndef MAP_FIXED_NOREPLACE\n#define MAP_FIXED_NOREPLACE 0x100000\n#endif\n",
     "#ifndef MAP_FIXED_NOREPLACE\n#if defined(__APPLE__)\n#define MAP_FIXED_NOREPLACE MAP_FIXED\n#else\n"
     "#define MAP_FIXED_NOREPLACE 0x100000\n#endif\n#endif\n"
     "#if defined(__APPLE__) && !defined(MAP_NORESERVE)\n#define MAP_NORESERVE 0\n#endif\n"),
    ("deps/openpsf/include/openpsf/openpsf.h",
     "\tchar* last_error;\n",
     "\tconst char* last_error;   // FF7Recomp: holds string literals (C++11)\n"),
]
n = 0
for rel, old, new in EDITS:
    p = ext / rel
    t = p.read_text()
    if new in t:
        continue
    if t.count(old) != 1:
        raise SystemExit(f"{rel}: layout changed; update FF7_IOS_DARWIN_HAND_EDITS in tools/apply_metal_overlay.sh")
    p.write_text(t.replace(old, new, 1))
    n += 1
print(f"Darwin hand edits applied: {n}" if n else "Darwin hand edits already applied")
PY12

