# bx / bimg / bgfx for Apple Metal (P1). Mirrors Android's cmake/bgfx.cmake pins
# but enables BGFX_CONFIG_RENDERER_METAL instead of Vulkan/GLES.
include("${CMAKE_CURRENT_LIST_DIR}/android_root.cmake")

set(BX_DIR   "${FF7_ROOT}/external/bx")
set(BIMG_DIR "${FF7_ROOT}/external/bimg")
set(BGFX_DIR "${FF7_ROOT}/external/bgfx")

foreach(dir BX_DIR BIMG_DIR BGFX_DIR)
  if(NOT EXISTS "${${dir}}")
    message(FATAL_ERROR "${dir} missing (${${dir}}). Run: bash tools/setup_android_core.sh")
  endif()
endforeach()

math(EXPR FF7_BGFX_DYNAMIC_INDEX_BUFFER_SIZE  "10 << 20")
math(EXPR FF7_BGFX_DYNAMIC_VERTEX_BUFFER_SIZE "30 << 20")
math(EXPR FF7_BGFX_MAX_RECT_CACHE             "8 << 10")

set(FF7_BX_DEFS BX_CONFIG_DEBUG=0 __STDC_LIMIT_MACROS __STDC_FORMAT_MACROS __STDC_CONSTANT_MACROS)

add_library(bx STATIC "${BX_DIR}/src/amalgamated.cpp")
target_include_directories(bx PUBLIC "${BX_DIR}/include" "${BX_DIR}/3rdparty")
target_compile_definitions(bx PUBLIC ${FF7_BX_DEFS})
target_compile_features(bx PUBLIC cxx_std_20)
target_compile_options(bx PRIVATE -w)

file(GLOB FF7_ASTC_SOURCES "${BIMG_DIR}/3rdparty/astc-encoder/source/*.cpp")
add_library(astcenc STATIC ${FF7_ASTC_SOURCES})
target_include_directories(astcenc PUBLIC "${BIMG_DIR}/3rdparty/astc-encoder/include")
target_compile_options(astcenc PRIVATE -w)
# Prefer the *target* arch (CMAKE_OSX_ARCHITECTURES) over the host CPU so Rosetta
# x86_64 builds on Apple Silicon do not pick up ASTCENC_NEON.
set(_ff7_astc_neon FALSE)
if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
  set(_ff7_astc_neon TRUE)
elseif(CMAKE_OSX_ARCHITECTURES MATCHES "x86_64")
  set(_ff7_astc_neon FALSE)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
  set(_ff7_astc_neon TRUE)
endif()
if(_ff7_astc_neon)
  target_compile_definitions(astcenc PRIVATE ASTCENC_NEON=1 ASTCENC_SSE=0 ASTCENC_AVX=0 ASTCENC_POPCNT=0 ASTCENC_F16C=0)
else()
  target_compile_definitions(astcenc PRIVATE ASTCENC_NEON=0 ASTCENC_SSE=41 ASTCENC_AVX=0 ASTCENC_POPCNT=0 ASTCENC_F16C=0)
endif()

add_library(bimg STATIC "${BIMG_DIR}/src/image.cpp")
target_include_directories(bimg PUBLIC "${BIMG_DIR}/include" PRIVATE "${BIMG_DIR}/3rdparty" "${BIMG_DIR}/3rdparty/astc-encoder/include")
target_link_libraries(bimg PUBLIC bx astcenc)
target_compile_options(bimg PRIVATE -w)

add_library(bimg_decode STATIC "${BIMG_DIR}/src/image_decode.cpp" "${BIMG_DIR}/src/image_decode_wic.cpp")
target_include_directories(bimg_decode PRIVATE "${BIMG_DIR}/3rdparty" "${BIMG_DIR}/3rdparty/tinyexr/deps")
target_compile_definitions(bimg_decode PRIVATE BIMG_CONFIG_PARSE_AVIF=0 BIMG_CONFIG_PARSE_HEIF=0)
target_link_libraries(bimg_decode PUBLIC bimg)
target_compile_options(bimg_decode PRIVATE -w)

add_library(bgfx STATIC "${BGFX_DIR}/src/amalgamated.cpp")
target_include_directories(bgfx
  PUBLIC  "${BGFX_DIR}/include"
  PRIVATE "${BGFX_DIR}/3rdparty" "${BGFX_DIR}/3rdparty/khronos" "${BGFX_DIR}/3rdparty/directx-headers/include/directx")
target_compile_definitions(bgfx
  PUBLIC  BGFX_CONFIG_RENDERER_METAL=1
  PRIVATE BGFX_CONFIG_RENDERER_VULKAN=0
          BGFX_CONFIG_RENDERER_OPENGLES=0
          BGFX_CONFIG_RENDERER_OPENGL=0
          BGFX_CONFIG_PREFER_DISCRETE_GPU=0
          BGFX_CONFIG_DYNAMIC_INDEX_BUFFER_SIZE=${FF7_BGFX_DYNAMIC_INDEX_BUFFER_SIZE}
          BGFX_CONFIG_DYNAMIC_VERTEX_BUFFER_SIZE=${FF7_BGFX_DYNAMIC_VERTEX_BUFFER_SIZE}
          BGFX_CONFIG_MAX_RECT_CACHE=${FF7_BGFX_MAX_RECT_CACHE})
target_link_libraries(bgfx PUBLIC bimg_decode bimg bx)
target_compile_options(bgfx PRIVATE -w)
if(APPLE)
  find_library(FF7_METAL_FRAMEWORK Metal REQUIRED)
  find_library(FF7_QUARTZ_FRAMEWORK QuartzCore REQUIRED)
  find_library(FF7_FOUNDATION_FRAMEWORK Foundation REQUIRED)
  find_library(FF7_IOKIT_FRAMEWORK IOKit REQUIRED)
  find_library(FF7_APPKIT_FRAMEWORK AppKit)
  target_link_libraries(bgfx PUBLIC
    ${FF7_METAL_FRAMEWORK}
    ${FF7_QUARTZ_FRAMEWORK}
    ${FF7_FOUNDATION_FRAMEWORK}
    ${FF7_IOKIT_FRAMEWORK})
  if(FF7_APPKIT_FRAMEWORK AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    target_link_libraries(bgfx PUBLIC ${FF7_APPKIT_FRAMEWORK})
  endif()
  # iOS: UIKit instead of AppKit for some platform bits.
  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    find_library(FF7_UIKIT_FRAMEWORK UIKit REQUIRED)
    target_link_libraries(bgfx PUBLIC ${FF7_UIKIT_FRAMEWORK})
  endif()
endif()
