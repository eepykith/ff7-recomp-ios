# Locate the fetched engine core, external/ff7-recomp-core (gitignored): the recompilation
# core of FF7Recomp for Android, fetched by tools/fetch_core.sh.
if(NOT DEFINED FF7_CORE_ROOT)
  get_filename_component(FF7_CORE_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../external/ff7-recomp-core" ABSOLUTE)
endif()
if(NOT EXISTS "${FF7_CORE_ROOT}/cmake/ff7core.cmake")
  message(FATAL_ERROR
    "Engine core missing at ${FF7_CORE_ROOT}. Run: bash tools/fetch_core.sh && bash tools/setup_core.sh")
endif()
set(FF7_ROOT "${FF7_CORE_ROOT}" CACHE PATH "ff7-recomp-core root" FORCE)
