#include "ff7_ios_companion.h"

#if defined(FF7_BUNDLE_GAME) && FF7_BUNDLE_GAME
extern int ff7_companion_json(char *out, int cap);   /* companion.cpp, in the core */
extern void ff7_companion_command(int cmd);

int ff7_ios_companion_json(char *out, int cap) { return ff7_companion_json(out, cap); }
void ff7_ios_companion_command(int cmd) { ff7_companion_command(cmd); }
#else
/* The launcher alone (FF7Recomp target): no game, no state. */
int ff7_ios_companion_json(char *out, int cap) {
  if (out && cap > 0) out[0] = '\0';
  return 0;
}
void ff7_ios_companion_command(int cmd) { (void)cmd; }
#endif
