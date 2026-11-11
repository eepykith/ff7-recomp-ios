cmake_minimum_required(VERSION 3.20)
# P0 is C-only. Enable CXX when FFNx/bgfx are vendored in P1.
project(FF7RecompIOS C)

set(CMAKE_C_STANDARD 11)

option(FF7_BUILD_TESTS "Build host API smoke tests" ON)
option(FF7_BUNDLE_GAME "Link a Mac-lifted game into the host (dev only)" OFF)

set(FF7_PLATFORM "host" CACHE STRING "host | ios | mac")

add_library(ff7_platform STATIC
  src/platform/ff7_host.c
  src/platform/ff7_platform.c
  src/ios/ff7_ios_window.c
)
# pthread for the window/pad locks (same split as Android's game thread vs UI).
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

# Local smoke binary — runs on Linux/macOS without Xcode.
add_executable(ff7_host_smoke tools/ff7_host_smoke.c)
target_link_libraries(ff7_host_smoke PRIVATE ff7_platform)

if(FF7_BUILD_TESTS)
  enable_testing()
  add_test(NAME host_smoke COMMAND ff7_host_smoke)
endif()

message(STATUS "FF7Recomp iOS P1: platform=${FF7_PLATFORM} bundle_game=${FF7_BUNDLE_GAME}")
