#include "ff7_host.h"

#include <stdio.h>
#include <string.h>

int main(void) {
  ff7_host_config cfg = {
      .width = 1280,
      .height = 720,
      .target_fps = 60,
      .metal = 1,
  };

  if (ff7_host_init(&cfg) != FF7_HOST_OK) {
    fprintf(stderr, "init failed: %s\n", ff7_host_message());
    return 1;
  }

  printf("version=%s\n", ff7_host_version());
  printf("init: %s\n", ff7_host_message());

  ff7_host_status st = ff7_host_boot(NULL);
  if (st != FF7_HOST_ERR_NO_GAME) {
    fprintf(stderr, "expected NO_GAME, got %d (%s)\n", (int)st,
            ff7_host_message());
    return 1;
  }
  printf("boot(null): %s\n", ff7_host_message());

  st = ff7_host_boot("/tmp/example.ff7pkg");
  if (st != FF7_HOST_ERR_UNSUPPORTED) {
    fprintf(stderr, "expected UNSUPPORTED, got %d (%s)\n", (int)st,
            ff7_host_message());
    return 1;
  }
  printf("boot(pkg): %s\n", ff7_host_message());

  if (strstr(ff7_host_message(), "P1") == NULL) {
    fprintf(stderr, "message should mention P1\n");
    return 1;
  }

  ff7_host_shutdown();
  printf("smoke ok\n");
  return 0;
}
