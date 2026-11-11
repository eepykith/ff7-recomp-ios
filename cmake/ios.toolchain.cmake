# iOS toolchain for CMake. Configure on a Mac with:
#   cmake -S . -B build-ios \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
#     -DFF7_PLATFORM=ios \
#     -GXcode
#
# This file is intentionally small; expand when FFNx/bgfx land in P1.

if(NOT DEFINED CMAKE_SYSTEM_NAME)
  set(CMAKE_SYSTEM_NAME iOS)
endif()

set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "" FORCE)
set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE NO)

# Minimum for GameController / modern Metal habits in the plan.
set(CMAKE_OSX_DEPLOYMENT_TARGET "17.0" CACHE STRING "" FORCE)

set(FF7_PLATFORM "ios" CACHE STRING "Host platform" FORCE)
