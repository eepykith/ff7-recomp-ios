#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* The game's live state for the status panel (the core's companion screen,
 * src/ffnx_port/companion.cpp): a JSON snapshot refreshed ten times a second on the game
 * thread. Copies it into out; returns its length, or 0 when no game is linked. */
int ff7_ios_companion_json(char *out, int cap);

/* Panel commands, run on the game thread: 1 speed 1x/2x/3x, 2 save state, 3 load state,
 * 4 random battles on/off, 5 battle enhancement on/off. */
void ff7_ios_companion_command(int cmd);

#ifdef __cplusplus
}
#endif
