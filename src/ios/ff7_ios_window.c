#include "ff7_ios_window.h"

#include "ff7_platform.h"

#include <stddef.h>

int ff7_ios_window_attach(ff7_ios_surface *surface) {
  if (!surface || !surface->metal_layer || surface->width <= 0 ||
      surface->height <= 0) {
    return -1;
  }
  ff7_platform_set_window(surface->metal_layer, surface->width, surface->height);
  return 0;
}

void ff7_ios_window_resize(int width, int height) {
  int cur_w = 0, cur_h = 0;
  void *layer = ff7_platform_window(&cur_w, &cur_h);
  if (width > 0 && height > 0) {
    ff7_platform_set_window(layer, width, height);
  }
}

void ff7_ios_window_detach(void) {
  ff7_platform_set_window(NULL, 0, 0);
}
