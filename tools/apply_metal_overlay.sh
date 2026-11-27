#!/usr/bin/env bash
# Patch the fetched engine core (external/ff7-recomp-core) for Apple Metal (idempotent).
# external/ is gitignored.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export ROOT
if [ ! -f "$ROOT/external/ff7-recomp-core/cmake/bgfx.cmake" ]; then
  echo "missing the core's cmake/bgfx.cmake — run tools/setup_core.sh" >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
import os

root = Path(os.environ["ROOT"])
core_root = root / "external" / "ff7-recomp-core"
bgfx = core_root / "cmake" / "bgfx.cmake"
display = core_root / "src" / "ffnx_bridge" / "ffnx_display.cpp"
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
BX_ALLOC="$ROOT/external/ff7-recomp-core/external/bx/src/allocator.cpp"
if [ -f "$BX_ALLOC" ] && ! grep -q 'malloc/malloc.h' "$BX_ALLOC"; then
  python3 - <<'PY2'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external/ff7-recomp-core/external/bx/src/allocator.cpp"
t = p.read_text()
old = "#include <malloc.h>\n"
new = "#if defined(__APPLE__)\n#\tinclude <malloc/malloc.h>\n#else\n#\tinclude <malloc.h>\n#endif\n"
if old in t:
    p.write_text(t.replace(old, new, 1))
    print("patched bx allocator.cpp for Apple")
PY2
fi

# Prefer -xobjective-c++ + CoreVideo (Metal amalgamated is ObjC++)
BGFX_CMAKE="$ROOT/external/ff7-recomp-core/cmake/bgfx.cmake"
if [ -f "$BGFX_CMAKE" ] && ! grep -q 'xobjective-c++' "$BGFX_CMAKE"; then
  python3 - <<'PY2'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external/ff7-recomp-core/cmake/bgfx.cmake"
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
HE="$ROOT/external/ff7-recomp-core/external/deps/highly_experimental"
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
core_root = root / "external" / "ff7-recomp-core"
cm = core_root / "cmake" / "ffnx.cmake"
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
stubs = core_root / "src" / "ffnx_port" / "link_stubs.cpp"
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
qb = root / "external" / "ff7-recomp-core" / "src" / "ffnx_port" / "quickboot.cpp"
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
cm = root / "external" / "ff7-recomp-core" / "cmake" / "ff7core.cmake"
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
python3 -I "$ROOT/tools/based_memory_port.py" "$ROOT/external/ff7-recomp-core" | tail -1
# The FFNx sites clang found with -Wint-to-pointer-cast / -Wformat (based_memory_port.py
# warnings|formats, run once on FFNx 0adf0b32), stored as a patch on top of the transform.
FFNX_DIR="$ROOT/external/ff7-recomp-core/external/FFNx"
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
# tools/fetch_core.sh.
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
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "external" / "FFNx" / "src" / "renderer.cpp"
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

CORE_DIR="$ROOT/external/ff7-recomp-core"
ff7_surface_resize undo
apply_once "$CORE_DIR"                   "$ROOT/patches/core-darwin.patch"
apply_once "$CORE_DIR/external/pcrecomp" "$ROOT/patches/pcrecomp-darwin.patch"
apply_once "$CORE_DIR/external/FFNx"     "$ROOT/patches/ffnx-darwin.patch"
ff7_surface_resize apply

# FF7_IOS_PAD_FRAME: tell the platform layer each game frame, so a tap shorter than a frame
# still reaches the game (ff7_platform_pad_frame in src/platform/ff7_platform.c).
python3 - <<'PY14'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "src" / "ffnx_port" / "companion.cpp"
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

# FF7_IOS_SOLOUD_PAUSE: let the platform layer stop and start FFNx's audio device (music,
# voices) while the game is paused; miniaudio stops it for a call and never starts it again.
python3 - <<'PY15'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "external" / "deps" / "soloud" / "src" / "backend" / "miniaudio" / "soloud_miniaudio.cpp"
t = p.read_text()
marker = "FF7_IOS_SOLOUD_PAUSE"
old = "    ma_device gDevice;\n"
new = old + """}
// FF7_IOS_SOLOUD_PAUSE: ff7_platform_set_paused (src/platform/ff7_platform.c)
extern "C" void ff7_soloud_pause(int paused)
{
    if (paused) ma_device_stop(&SoLoud::gDevice);
    else ma_device_start(&SoLoud::gDevice);
}
namespace SoLoud
{
"""
if marker in t:
    print("soloud_miniaudio.cpp already has FF7_IOS_SOLOUD_PAUSE")
else:
    if t.count(old) != 1:
        raise SystemExit("soloud_miniaudio.cpp layout changed; update FF7_IOS_SOLOUD_PAUSE in tools/apply_metal_overlay.sh")
    p.write_text(t.replace(old, new, 1))
    print("patched soloud_miniaudio.cpp: FF7_IOS_SOLOUD_PAUSE")
PY15

# FF7_IOS_SOLOUD_SESSION: FFNx's audio device sets the app's audio session; miniaudio's default
# asks for PlayAndRecord and falls back to Playback, which ignores the silent switch. Use
# SoloAmbient, as games do: the silent switch mutes the game, other apps' music stops.
python3 - <<'PY16'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "external" / "deps" / "soloud" / "src" / "backend" / "miniaudio" / "soloud_miniaudio.cpp"
t = p.read_text()
marker = "FF7_IOS_SOLOUD_SESSION"
old = "        if (ma_device_init(NULL, &config, &gDevice) != MA_SUCCESS)\n"
new = """        // FF7_IOS_SOLOUD_SESSION (tools/apply_metal_overlay.sh)
        static ma_context sContext;
        ma_context_config cc = ma_context_config_init();
        cc.coreaudio.sessionCategory = ma_ios_session_category_solo_ambient;
        ma_context* ctx = ma_context_init(NULL, 0, &cc, &sContext) == MA_SUCCESS ? &sContext : NULL;
        if (ma_device_init(ctx, &config, &gDevice) != MA_SUCCESS)
"""
if marker in t:
    print("soloud_miniaudio.cpp already has FF7_IOS_SOLOUD_SESSION")
else:
    if t.count(old) != 1:
        raise SystemExit("soloud_miniaudio.cpp layout changed; update FF7_IOS_SOLOUD_SESSION in tools/apply_metal_overlay.sh")
    p.write_text(t.replace(old, new, 1))
    print("patched soloud_miniaudio.cpp: FF7_IOS_SOLOUD_SESSION")
PY16

# FF7_IOS_UN7Z: the launcher's .7z unpacker (src/android/un7z.c) on Apple: fdatasync and
# posix_fadvise are Linux only; fsync keeps the written pages from piling up there.
python3 - <<'PY17'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "src" / "android" / "un7z.c"
t = p.read_text()
marker = "FF7_IOS_UN7Z"
old = ("                fdatasync(fd);\n"
       "                posix_fadvise(fd, 0, (off_t)out, POSIX_FADV_DONTNEED);\n")
new = ("#ifdef __APPLE__   /* FF7_IOS_UN7Z */\n"
       "                fsync(fd);\n"
       "#else\n" + old + "#endif\n")
if marker in t:
    print("un7z.c already has FF7_IOS_UN7Z")
else:
    if t.count(old) != 1:
        raise SystemExit("un7z.c layout changed; update FF7_IOS_UN7Z in tools/apply_metal_overlay.sh")
    p.write_text(t.replace(old, new, 1))
    print("patched un7z.c: FF7_IOS_UN7Z")
PY17

# FF7_IOS_SS_DEFAULT_TEX: loading a save state with mods turned field backgrounds black. A texture
# set whose other palettes have no replacement image of their own shares one fallback image
# (gl_texture_set::default_texture_id, FFNx saveload.cpp). The set lives in guest memory, so a
# load restored the id from the moment of the save, whose texture the load had just deleted, and
# the rebuild reused it. Forget it before the rebuild; delete each GPU texture once (the fallback
# is shared by several palettes).
python3 - <<'PY18'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "src" / "ffnx_port" / "savestate_ffnx.cpp"
t = p.read_text()
marker = "FF7_IOS_SS_DEFAULT_TEX"
old_del = """void ss_before_load(void *) {
    for (uint32_t a : g_sets) {
        struct ff7_texture_set *ts = (struct ff7_texture_set *)G2H(a);
        struct gl_texture_set *gl = ts->ogl.gl_set;
        uint32_t *handles = ts->texturehandle;
        if (!gl || !handles) continue;
        for (uint32_t i = 0; i < gl->textures; i++)
            if (handles[i]) newRenderer.deleteTexture(handles[i]);
        for (auto &kv : gl->additional_textures) if (kv.second) newRenderer.deleteTexture(kv.second);
        for (auto &kv : gl->animated_textures) if (kv.second) newRenderer.deleteTexture(kv.second);
    }
    g_sets.clear();
}"""
new_del = """void ss_before_load(void *) {
    std::set<uint32_t> gone;   // FF7_IOS_SS_DEFAULT_TEX: each GPU texture once (palettes share the fallback)
    for (uint32_t a : g_sets) {
        struct ff7_texture_set *ts = (struct ff7_texture_set *)G2H(a);
        struct gl_texture_set *gl = ts->ogl.gl_set;
        uint32_t *handles = ts->texturehandle;
        if (!gl || !handles) continue;
        for (uint32_t i = 0; i < gl->textures; i++)
            if (handles[i]) gone.insert(handles[i]);
        if (gl->default_texture_id) gone.insert(gl->default_texture_id);
        for (auto &kv : gl->additional_textures) if (kv.second) gone.insert(kv.second);
        for (auto &kv : gl->animated_textures) if (kv.second) gone.insert(kv.second);
    }
    for (uint32_t h : gone) newRenderer.deleteTexture(h);
    g_sets.clear();
}"""
old_reb = """        for (short slot = RendererTextureSlot::TEX_NML; slot < RendererTextureSlot::COUNT; slot++) gl->additional_textures[slot] = 0;
"""
new_reb = old_reb + """        gl->default_texture_id = 0;   // FF7_IOS_SS_DEFAULT_TEX: the saved moment's, deleted: load it again
"""
if marker in t:
    print("savestate_ffnx.cpp already has FF7_IOS_SS_DEFAULT_TEX")
else:
    if t.count(old_del) != 1 or t.count(old_reb) != 1:
        raise SystemExit("savestate_ffnx.cpp layout changed; update FF7_IOS_SS_DEFAULT_TEX in tools/apply_metal_overlay.sh")
    p.write_text(t.replace(old_del, new_del, 1).replace(old_reb, new_reb, 1))
    print("patched savestate_ffnx.cpp: FF7_IOS_SS_DEFAULT_TEX")
PY18

# FF7_IOS_SS_FILES: the game keeps open files in its own memory (ff7_file -> lgp_file), and for a
# plain file (not inside an LGP) lgp_file holds the host's FILE*. A save state carries that
# pointer: loaded in a later run (or after the file was closed) it named a FILE that no longer
# exists, and the next read crashed (battle sound effects: seek_file -> fseek -> SIGSEGV). FFNx's
# file layer now reports opens and closes; the state keeps each open file and its position; a
# load closes the current FILEs and reopens the state's at their positions (never with "w": that
# would empty the file).
python3 - <<'PY19'
from pathlib import Path
import os
root = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core"
f = root / "external" / "FFNx" / "src" / "ff7" / "file.cpp"
t = f.read_text()
marker = "FF7_IOS_SS_FILES"
if marker in t:
    print("file.cpp already has FF7_IOS_SS_FILES")
else:
    old_close = "void close_file(struct ff7_file *file)\n{\n\tif(!file) return;\n"
    new_close = ("extern \"C\" void ffnx_ss_file_opened(struct ff7_file *file);   // FF7_IOS_SS_FILES: src/ffnx_port/savestate_ffnx.cpp\n"
                 "extern \"C\" void ffnx_ss_file_closed(struct ff7_file *file);\n"
                 "extern \"C\" FILE *ffnx_file_host_fd(struct ff7_file *file) { return file && file->fd && !file->context.use_lgp ? file->fd->fd : nullptr; }\n"
                 "extern \"C\" void ffnx_file_set_host_fd(struct ff7_file *file, FILE *fd) { if (file && file->fd && !file->context.use_lgp) file->fd->fd = fd; }\n\n"
                 + old_close + "\tffnx_ss_file_closed(file);   // FF7_IOS_SS_FILES\n")
    old_open = "\t\tif(!ret->fd->fd) goto error;\n\t}\n\n\treturn ret;\n"
    new_open = "\t\tif(!ret->fd->fd) goto error;\n\t\tffnx_ss_file_opened(ret);   // FF7_IOS_SS_FILES\n\t}\n\n\treturn ret;\n"
    if t.count(old_close) != 1 or t.count(old_open) != 1:
        raise SystemExit("file.cpp layout changed; update FF7_IOS_SS_FILES in tools/apply_metal_overlay.sh")
    f.write_text(t.replace(old_close, new_close, 1).replace(old_open, new_open, 1))
    print("patched file.cpp: FF7_IOS_SS_FILES")

s = root / "src" / "ffnx_port" / "savestate_ffnx.cpp"
u = s.read_text()
if marker in u:
    print("savestate_ffnx.cpp already has FF7_IOS_SS_FILES")
else:
    old_reg = """struct Register {
    Register() { ff7_savestate_register(&g_hook); ff7_savestate_register(&g_scene_hook); ff7_savestate_register(&g_prompts_hook);
                 ff7_savestate_register(&g_deferred_hook); }
} g_register;"""
    new_reg = """// ---- FF7_IOS_SS_FILES: the game's open plain files (ff7/file.cpp). Their FILE* is host memory
// kept in guest memory: a state holds it from its own moment and run. The state keeps each open
// file and its position; a load closes the current FILEs and reopens the state's.
std::set<uint32_t> g_files;                // live ff7_file objects (guest addresses)
struct SavedFile { uint32_t file; uint32_t pos; };
std::vector<SavedFile> g_files_restored;
bool g_files_have;                         // the state has the record (states from before 0.2.4 do not)
std::vector<std::pair<uint32_t, std::string>> g_files_before;   // open when the load began: their names

int files_save(void *, ff7_ss_writer put, void *buf) {
    std::vector<SavedFile> v;
    for (uint32_t a : g_files) {
        FILE *fd = ffnx_file_host_fd(guest::ptr_of<struct ff7_file>(a));
        long pos = fd ? std::ftell(fd) : -1;
        v.push_back({ a, pos < 0 ? 0u : (uint32_t)pos });
    }
    return put(buf, v.data(), v.size() * sizeof(SavedFile));
}
void files_before_load(void *) {
    g_files_before.clear();
    for (uint32_t a : g_files) {
        struct ff7_file *f = guest::ptr_of<struct ff7_file>(a);
        if (f && f->name) g_files_before.emplace_back(a, std::string((const char *)f->name));
        if (FILE *fd = ffnx_file_host_fd(f)) { std::fclose(fd); ffnx_file_set_host_fd(f, nullptr); }
    }
    g_files.clear();
}
void files_restore(void *, const void *data, size_t n) {
    g_files_have = true;
    g_files_restored.resize(n / sizeof(SavedFile));
    if (!g_files_restored.empty()) std::memcpy(g_files_restored.data(), data, g_files_restored.size() * sizeof(SavedFile));
}
void files_after_load(void *) {
    int reopened = 0, missing = 0;
    if (!g_files_have) {
        // an older state: no record. The files open now that the state's memory has at the same
        // place under the same name (audio.dat, opened once at start-up) are reopened at 0; the
        // game seeks before it reads.
        g_files_restored.clear();
        for (const auto &b : g_files_before) {
            struct ff7_file *f = guest::ptr_of<struct ff7_file>(b.first);
            if (f && f->fd && !f->context.use_lgp && f->name && b.second == (const char *)f->name)
                g_files_restored.push_back({ b.first, 0 });
        }
    }
    g_files_have = false;
    g_files_before.clear();
    for (const SavedFile &s : g_files_restored) {
        struct ff7_file *f = guest::ptr_of<struct ff7_file>(s.file);
        if (!f || !f->fd || f->context.use_lgp || !f->name) continue;
        const char *name = (const char *)f->name;
        const char *mode = f->context.mode == FF7_FMODE_READ ? "rb" : f->context.mode == FF7_FMODE_READ_TEXT ? "r" : "r+b";
        FILE *fd = fopen(name, mode);
        if (!fd && std::strcmp(mode, "r+b") == 0) fd = fopen(name, "rb");
        ffnx_file_set_host_fd(f, fd);
        if (fd) { std::fseek(fd, (long)s.pos, SEEK_SET); g_files.insert(s.file); reopened++; }
        else { missing++; ffnx_error("savestate: could not reopen %s\\n", name); }
    }
    g_files_restored.clear();
    ffnx_info("savestate: %d open file(s) reopened%s\\n", reopened, missing ? " (some missing)" : "");
}
const ff7_savestate_hook g_files_hook = { "ffnx-files", nullptr, files_save, files_before_load, files_restore, files_after_load };

struct Register {
    Register() { ff7_savestate_register(&g_hook); ff7_savestate_register(&g_scene_hook); ff7_savestate_register(&g_prompts_hook);
                 ff7_savestate_register(&g_deferred_hook); ff7_savestate_register(&g_files_hook); }
} g_register;"""
    old_decl = """extern "C" void ffnx_ss_texture_set_created(uint32_t ts) { g_sets.insert(ts); }"""
    new_decl = old_decl + """
extern "C" FILE *ffnx_file_host_fd(struct ff7_file *file);                 // FF7_IOS_SS_FILES: ff7/file.cpp
extern "C" void ffnx_file_set_host_fd(struct ff7_file *file, FILE *fd);
namespace { extern std::set<uint32_t> g_files; }
extern "C" void ffnx_ss_file_opened(struct ff7_file *file) { g_files.insert(guest::to_va(file)); }
extern "C" void ffnx_ss_file_closed(struct ff7_file *file) { g_files.erase(guest::to_va(file)); }"""
    if u.count(old_reg) != 1 or u.count(old_decl) != 1:
        raise SystemExit("savestate_ffnx.cpp layout changed; update FF7_IOS_SS_FILES in tools/apply_metal_overlay.sh")
    u = u.replace(old_reg, new_reg, 1).replace(old_decl, new_decl, 1)
    s.write_text(u)
    print("patched savestate_ffnx.cpp: FF7_IOS_SS_FILES")
PY19

# FF7_IOS_GA_DOUBLE_FREE: a free of a guest block that is already free (its header cleared by
# the first free, the block in the free list) aborted the game; seen once on an iPhone right
# after loading a save state, the game freeing a texture's image data twice. Such a free is now
# logged with its native backtrace and ignored, which is safe: the block is free either way.
# Anything else that does not look like a live block still stops the game.
python3 - <<'PY20'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "external" / "pcrecomp" / "runtime" / "win32hle" / "guest_alloc.c"
t = p.read_text()
marker = "FF7_IOS_GA_DOUBLE_FREE"
old = """void guest_free(void *p) {
    if (!p) return;
    pthread_mutex_lock(&g_ga_lock);
    if (!g_arena_hi) { free(p); pthread_mutex_unlock(&g_ga_lock); return; }
    ga_hdr *h = ga_header(p);"""
new = """/* FF7_IOS_GA_DOUBLE_FREE: is this block's header inside a free range? (caller holds the lock) */
static int ga_is_free(uint32_t a) {
    for (int i = 0; i < g_free_n; i++)
        if (a >= g_free[i].addr && a < g_free[i].addr + g_free[i].size) return 1;
    return 0;
}

void guest_free(void *p) {
    if (!p) return;
    pthread_mutex_lock(&g_ga_lock);
    if (!g_arena_hi) { free(p); pthread_mutex_unlock(&g_ga_lock); return; }
    {   /* FF7_IOS_GA_DOUBLE_FREE: already free -> log and ignore */
        uintptr_t a = (uintptr_t)p - (uintptr_t)g_mem_base;
        if (a >= (uintptr_t)g_arena_lo + GA_HDR && a < g_arena_hi) {
            ga_hdr *f = (ga_hdr *)((uintptr_t)p - GA_HDR);
            if (f->magic == 0 && ga_is_free((uint32_t)(a - GA_HDR))) {
                pthread_mutex_unlock(&g_ga_lock);
                fprintf(stderr, "[guest_alloc] double free of 0x%08X ignored (already free)\\n", (uint32_t)a);
                void *bt[24];
                int n = backtrace(bt, 24);
                backtrace_symbols_fd(bt, n, 2);
                return;
            }
        }
    }
    ga_hdr *h = ga_header(p);"""
if marker in t:
    print("guest_alloc.c already has FF7_IOS_GA_DOUBLE_FREE")
else:
    if t.count(old) != 1 or "#include <stdio.h>" not in t:
        raise SystemExit("guest_alloc.c layout changed; update FF7_IOS_GA_DOUBLE_FREE in tools/apply_metal_overlay.sh")
    t = t.replace(old, new, 1).replace("#include <stdio.h>", "#include <stdio.h>\n#include <execinfo.h>   /* FF7_IOS_GA_DOUBLE_FREE */", 1)
    p.write_text(t)
    print("patched guest_alloc.c: FF7_IOS_GA_DOUBLE_FREE")
PY20

# FF7_IOS_SS_BUFFERS: FFNx keeps its texture conversion buffer (image_data_cache, common.cpp) in
# game memory across frames, but its address in a host static. A load replaces game memory
# with the state's, so the statics named memory the loaded state uses for something else, and the
# next texture conversion (the first scene change) wrote over it: on an iPhone the header of a
# texture's image data, and the game aborted when it freed that texture. The state now records
# the buffer's address in its own memory and a load points the static there (before the texture
# rebuild, which converts textures); a state without the record forgets it, never freeing memory
# that is no longer its own.
python3 - <<'PY21'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "src" / "ffnx_port" / "savestate_ffnx.cpp"
t = p.read_text()
marker = "FF7_IOS_SS_BUFFERS"
old_reg = "ff7_savestate_register(&g_files_hook); }"
new_reg = old_reg
code = """
// ---- FF7_IOS_SS_BUFFERS: FFNx's texture conversion buffer is in game memory, its address in a host static
extern uint32_t *image_data_cache;          // common.cpp
extern uint32_t image_data_size_cache;
namespace {
struct SavedBuffers { uint32_t cache, cache_size; };
int buffers_save(void *, ff7_ss_writer put, void *buf) {
    SavedBuffers b{ guest::to_va(image_data_cache), image_data_size_cache };
    return put(buf, &b, sizeof b);
}
uint32_t g_cache_was;
void buffers_before_load(void *) {
    // the memory they point to is about to become the state's: forget it (never free it)
    g_cache_was = guest::to_va(image_data_cache);
    image_data_cache = nullptr;
    image_data_size_cache = 0;
}
void buffers_restore(void *, const void *data, size_t n) {
    if (n != sizeof(SavedBuffers)) return;   // an older record: stay forgotten, allocated afresh
    SavedBuffers b;
    std::memcpy(&b, data, sizeof b);
    image_data_cache = guest::ptr_of<uint32_t>(b.cache);
    image_data_size_cache = image_data_cache ? b.cache_size : 0;
    ffnx_info("savestate: texture buffer 0x%08X -> 0x%08X (the state's)\\n", g_cache_was, b.cache);
}
// its restore runs as the state's records are read, before any hook's after_load (the texture
// rebuild converts textures with image_data_cache)
const ff7_savestate_hook g_buffers_hook = { "ffnx-buffers", nullptr, buffers_save, buffers_before_load, buffers_restore, nullptr };
struct RegisterBuffers { RegisterBuffers() { ff7_savestate_register(&g_buffers_hook); } } g_register_buffers;
}  // namespace
"""
if marker in t:
    print("savestate_ffnx.cpp already has FF7_IOS_SS_BUFFERS")
else:
    if t.count(old_reg) != 1 or "extern \"C\" int ff7_ss_driver_mode(void) {" not in t:
        raise SystemExit("savestate_ffnx.cpp layout changed; update FF7_IOS_SS_BUFFERS in tools/apply_metal_overlay.sh")
    t = t.replace(old_reg, new_reg, 1)
    t = t.replace("extern \"C\" int ff7_ss_driver_mode(void) {", code + "\nextern \"C\" int ff7_ss_driver_mode(void) {", 1)
    p.write_text(t)
    print("patched savestate_ffnx.cpp: FF7_IOS_SS_BUFFERS")
PY21

# FF7_IOS_SS_SCRATCH: ffnx_guest_scratch (gl.cpp's facial vertices, ...) keeps a per-call-site
# buffer in game memory with its address in a static: after a save state was loaded it named
# memory the loaded state uses for something else, and when the buffer next grew, freeing the
# old one aborted the game (seen on an iPhone in the field). A load now bumps a counter; each
# scratch buffer sees it and starts afresh, never freeing memory that is no longer its own.
python3 - <<'PY22'
from pathlib import Path
import os
root = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "src" / "ffnx_port"
marker = "FF7_IOS_SS_SCRATCH"
h = root / "include" / "ffnx_guest.h"
t = h.read_text()
old = """template <typename T, int Site> inline T *ffnx_guest_scratch(const T *data, size_t n) {
    static T *buf = nullptr;
    static size_t cap = 0;
    if (n > cap) {"""
new = """extern "C" uint32_t ffnx_ss_load_generation;   // FF7_IOS_SS_SCRATCH: bumped by every save-state load
template <typename T, int Site> inline T *ffnx_guest_scratch(const T *data, size_t n) {
    static T *buf = nullptr;
    static size_t cap = 0;
    static uint32_t gen = 0;
    if (gen != ffnx_ss_load_generation) {   // a load replaced game memory: buf is not ours any more
        gen = ffnx_ss_load_generation;
        buf = nullptr;
        cap = 0;
    }
    if (n > cap) {"""
if marker in t:
    print("ffnx_guest.h already has FF7_IOS_SS_SCRATCH")
else:
    if t.count(old) != 1:
        raise SystemExit("ffnx_guest.h layout changed; update FF7_IOS_SS_SCRATCH in tools/apply_metal_overlay.sh")
    h.write_text(t.replace(old, new, 1))
    print("patched ffnx_guest.h: FF7_IOS_SS_SCRATCH")
c = root / "savestate_ffnx.cpp"
u = c.read_text()
old2 = """void buffers_before_load(void *) {"""
new2 = """}  // namespace
extern "C" uint32_t ffnx_ss_load_generation = 0;   // FF7_IOS_SS_SCRATCH (include/ffnx_guest.h)
namespace {
void buffers_before_load(void *) {
    ffnx_ss_load_generation++;   // FF7_IOS_SS_SCRATCH"""
if marker in u:
    print("savestate_ffnx.cpp already has FF7_IOS_SS_SCRATCH")
else:
    if u.count(old2) != 1:
        raise SystemExit("savestate_ffnx.cpp layout changed (needs FF7_IOS_SS_BUFFERS first); update FF7_IOS_SS_SCRATCH")
    c.write_text(u.replace(old2, new2, 1))
    print("patched savestate_ffnx.cpp: FF7_IOS_SS_SCRATCH")
PY22

# FF7_IOS_WIDESCREEN_SWIRL: the battle swirl's grid (ff7_data.h, swirl_grid) is a game address
# that widescreen's ff7_swirl_init_widescreen writes through natively. based_memory_port.py's
# reinterpret_cast pattern cannot match its type (vector4<short> (*)[9]), so it stayed a raw
# guest address: with 16:9 on, every battle crashed as the swirl began (SIGSEGV at the guest VA).
python3 - <<'PY23'
from pathlib import Path
import os
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "external" / "FFNx" / "src" / "ff7_data.h"
t = p.read_text()
old = "reinterpret_cast<vector4<short> (*)[9]>(get_absolute_value(ff7_externals.swirl_enter_sub_401810, 0xE) + 0xC88);"
new = "reinterpret_cast<vector4<short> (*)[9]>(G2H(get_absolute_value(ff7_externals.swirl_enter_sub_401810, 0xE) + 0xC88));   // FF7_IOS_WIDESCREEN_SWIRL"
if "FF7_IOS_WIDESCREEN_SWIRL" in t:
    print("ff7_data.h already has FF7_IOS_WIDESCREEN_SWIRL")
else:
    if t.count(old) != 1:
        raise SystemExit("ff7_data.h layout changed; update FF7_IOS_WIDESCREEN_SWIRL in tools/apply_metal_overlay.sh")
    p.write_text(t.replace(old, new, 1))
    print("patched ff7_data.h: FF7_IOS_WIDESCREEN_SWIRL")
PY23

# FF7_IOS_AUDIO_OBJCXX: on iOS miniaudio includes AVFoundation (its audio session), which
# needs Objective-C++; compile SoLoud's miniaudio backend that way on Apple mobile targets.
python3 - <<'PY6'
from pathlib import Path
import os
root = Path(os.environ["ROOT"])
cm = root / "external" / "ff7-recomp-core" / "cmake" / "ffnx_audio.cmake"
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
cm = root / "external" / "ff7-recomp-core" / "cmake" / "ffnx.cmake"
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
root = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "external"
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
# sound effects through AAudio on Android. On Apple, core-darwin.patch splits its mix loop
# into mix_frames() (the AAudio callback calls it unchanged) and has mixer_start() open a CoreAudio
# output unit, src/hle_overlay/ff7_dsound_coreaudio.c, built into ff7_core here. If no output can
# be opened the mixer stays silent and the game runs on.
python3 - <<'PY9'
from pathlib import Path
import os
root = Path(os.environ["ROOT"])
cm = root / "external" / "ff7-recomp-core" / "cmake" / "ff7core.cmake"
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
cm = root / "external" / "ff7-recomp-core" / "cmake" / "ffnx.cmake"
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
p = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "src" / "ffnx_port" / "quickboot.cpp"
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
ext = Path(os.environ["ROOT"]) / "external" / "ff7-recomp-core" / "external"
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

