#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Start ff7_boot_and_run on a 64 MB detached pthread (Android parity).
 * Returns 0 on start, 1 if already started, -1 if FFNx is not linked, -2 on
 * pthread failure. */
int ff7_ios_start_game_thread(const char *game_dir);
int ff7_ios_game_thread_started(void);

#ifdef __cplusplus
}
#endif
