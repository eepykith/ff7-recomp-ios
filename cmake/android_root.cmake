# Locate the fetched Android core (gitignored under external/).
if(NOT DEFINED FF7_ANDROID_ROOT)
  get_filename_component(FF7_ANDROID_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../external/ff7-recomp-android" ABSOLUTE)
endif()
if(NOT EXISTS "${FF7_ANDROID_ROOT}/cmake/ff7core.cmake")
  message(FATAL_ERROR
    "Android core missing at ${FF7_ANDROID_ROOT}. Run: bash tools/fetch_android_core.sh && bash tools/setup_android_core.sh")
endif()
set(FF7_ROOT "${FF7_ANDROID_ROOT}" CACHE PATH "ff7-recomp-android root" FORCE)
