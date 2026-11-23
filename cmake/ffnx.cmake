# Link the Android FFNx/ff7_core stack into this host, with Metal bgfx.
# Prerequisites:
#   bash tools/fetch_android_core.sh
#   bash tools/setup_android_core.sh
#   python3 tools/import_game.py / lift (generated/recomp under the Android tree)
include("${CMAKE_CURRENT_LIST_DIR}/android_root.cmake")

# Ensure Metal overlay scripts have been applied (idempotent).
execute_process(
  COMMAND bash "${CMAKE_CURRENT_LIST_DIR}/../tools/apply_metal_overlay.sh"
  RESULT_VARIABLE _ff7_metal_rc
)
if(NOT _ff7_metal_rc EQUAL 0)
  message(FATAL_ERROR "tools/apply_metal_overlay.sh failed (${_ff7_metal_rc})")
endif()

set(FF7_WITH_BGFX ON CACHE BOOL "" FORCE)
set(FF7_WITH_FFNX ON CACHE BOOL "" FORCE)
include("${FF7_ROOT}/cmake/ff7core.cmake")

# Rosetta x86_64 on Apple Silicon: android ffnx_deps always enables libpng NEON.
if(APPLE AND CMAKE_OSX_ARCHITECTURES MATCHES "x86_64" AND TARGET ffnx_png)
  get_target_property(_ff7_png_defs ffnx_png COMPILE_DEFINITIONS)
  if(_ff7_png_defs)
    list(FILTER _ff7_png_defs EXCLUDE REGEX "^PNG_ARM_NEON_OPT=")
  else()
    set(_ff7_png_defs "")
  endif()
  list(APPEND _ff7_png_defs PNG_ARM_NEON_OPT=0)
  set_target_properties(ffnx_png PROPERTIES COMPILE_DEFINITIONS "${_ff7_png_defs}")
  get_target_property(_ff7_png_srcs ffnx_png SOURCES)
  if(_ff7_png_srcs)
    list(FILTER _ff7_png_srcs EXCLUDE REGEX "/arm/")
    set_property(TARGET ffnx_png PROPERTY SOURCES "${_ff7_png_srcs}")
  endif()
endif()
