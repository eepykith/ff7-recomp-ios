/* ff7_ios_mods.c: the mod layer's report for the launcher, in builds with or without the game. */
#include "ff7_unzip.h"
#include <stddef.h>

/* The core's (src/mods/mods.cpp) replaces this default in the full app; the launcher alone
 * has no mod layer. */
__attribute__((weak)) char *ff7_mods_conflicts_json(const char *profile_path) {
  (void)profile_path;
  return NULL;
}

char *ff7_ios_mods_conflicts_json(const char *profile_path) {
  return ff7_mods_conflicts_json(profile_path);
}

/* ff7_ios_modinfo.cpp (full app only) replaces this. */
__attribute__((weak)) char *ff7_ios_mod_info_json(const char *path) {
  (void)path;
  return NULL;
}
