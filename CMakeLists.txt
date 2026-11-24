cmake_minimum_required(VERSION 3.20)
project(FF7RecompIOS C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)

option(FF7_BUNDLE_GAME "Link Mac-lifted game + FFNx/Metal (dev only)" OFF)

set(FF7_PLATFORM "host" CACHE STRING "host | ios | mac")

add_library(ff7_platform STATIC
  src/platform/ff7_host.c
  src/platform/ff7_platform.c
  src/ios/ff7_ios_window.c
  src/ios/ff7_ios_boot.c
)
find_package(Threads REQUIRED)
target_link_libraries(ff7_platform PUBLIC Threads::Threads)
target_include_directories(ff7_platform
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src/platform
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ios
)
target_compile_definitions(ff7_platform
  PUBLIC
    FF7_PLATFORM_${FF7_PLATFORM}=1
)
if(FF7_BUNDLE_GAME)
  target_compile_definitions(ff7_platform PUBLIC FF7_BUNDLE_GAME=1)
endif()

add_library(ff7_engine INTERFACE)
target_link_libraries(ff7_engine INTERFACE ff7_platform)

if(FF7_BUNDLE_GAME)
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ffnx.cmake")
  target_link_libraries(ff7_engine INTERFACE ff7_core)
endif()


if(FF7_BUNDLE_GAME)
  # Dev runner: boots the lifted game against a real CAMetalLayer (Mac) / stub (else).
  add_executable(ff7_metal_boot tools/ff7_metal_boot.c)
  target_link_libraries(ff7_metal_boot PRIVATE ff7_engine)
  if(APPLE)
    target_sources(ff7_metal_boot PRIVATE src/mac/ff7_mac_metal_window.mm)
    target_include_directories(ff7_metal_boot PRIVATE src/mac)
    # Full Darwin FFNx link: bash tools/darwin_link_metal_boot.sh after cmake build.
    find_library(FF7_COREMEDIA_FRAMEWORK CoreMedia REQUIRED)
    find_library(FF7_VIDEOTOOLBOX_FRAMEWORK VideoToolbox REQUIRED)
    find_library(FF7_AUDIOTOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
    target_link_libraries(ff7_metal_boot PRIVATE
      ${FF7_COREMEDIA_FRAMEWORK}
      ${FF7_VIDEOTOOLBOX_FRAMEWORK}
      ${FF7_AUDIOTOOLBOX_FRAMEWORK})
  endif()
endif()


message(STATUS "FF7Recomp iOS P1: platform=${FF7_PLATFORM} bundle_game=${FF7_BUNDLE_GAME}")
