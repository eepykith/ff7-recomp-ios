/* Dev host: start ff7_boot_and_run with a real CAMetalLayer window.
 * Usage: ff7_metal_boot [game_dir]
 * Default game_dir: ./game (imported Steam tree; never commit).
 */
#include "ff7_host.h"
#include "ff7_platform.h"
#include "ff7_ios_boot.h"
#include "ff7_mac_metal_window.h"

#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
  const char *game_dir = (argc > 1) ? argv[1] : "game";
  ff7_host_config cfg = {.width = 1280, .height = 720, .target_fps = 60, .metal = 1};
  if (ff7_host_init(&cfg) != FF7_HOST_OK) {
    fprintf(stderr, "host init failed: %s\n", ff7_host_message());
    return 1;
  }
  if (ff7_mac_metal_window_create(cfg.width, cfg.height) != 0) {
    fprintf(stderr, "metal window create failed\n");
    return 1;
  }
  ff7_host_status st = ff7_host_boot(game_dir);
  fprintf(stderr, "boot status=%d msg=%s\n", (int)st, ff7_host_message());
  if (st != FF7_HOST_OK) {
    return 2;
  }
  /* Keep process alive while the detached game thread runs. */
  for (;;) {
    ff7_mac_metal_window_pump();
    usleep(16000);
  }
  return 0;
}
