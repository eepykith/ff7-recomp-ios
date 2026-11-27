#pragma once
/* Unpacking mod downloads on iOS (ModDownloader.swift): .zip here, .7z with the engine
 * core's un7z.c (the LZMA SDK's 7z reader). Both report progress and can be cancelled from
 * another thread. */
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Unpack `archive` (a .zip, ZIP64 included; stored or deflated entries) into `outdir`.
 * 0 on success; otherwise -1 with the reason in err. */
int ff7_unzip(const char *archive, const char *outdir, char *err, size_t errlen);
void ff7_unzip_cancel(void);
void ff7_unzip_progress(unsigned long long *done, unsigned long long *total);

/* src/android/un7z.c in the engine core */
int ff7_un7z(const char *archive, const char *outdir, char *err, size_t errlen);
void ff7_un7z_cancel(void);
void ff7_un7z_progress(unsigned long long *done, unsigned long long *total);

/* The mod profile loaded as the game loads it, as JSON: the game files two enabled mods both
 * replace, Forbid/Require entries (src/mods/mods.h ff7_mods_conflicts_json). NULL in a build
 * without the game (the launcher alone). free() the result. */
char *ff7_ios_mods_conflicts_json(const char *profile_path);

/* A mod (folder or .iro) described as JSON: name, author, version, category, options
 * [{id,name,type,default,description,values:[{value,name}]}], requires, forbids
 * (ff7_ios_modinfo.cpp). NULL in a build without the game. free() the result. */
char *ff7_ios_mod_info_json(const char *path);

#ifdef __cplusplus
}
#endif
