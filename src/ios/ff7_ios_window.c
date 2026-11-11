#include "ff7_ios_window.h"

#include <stddef.h>

static ff7_ios_surface g_surface;

int ff7_ios_window_attach(ff7_ios_surface *surface) {
  if (!surface || !surface->metal_layer || surface->width <= 0 ||
      surface->height <= 0) {
    return -1;
  }
  g_surface = *surface;
  return 0;
}

void ff7_ios_window_resize(int width, int height) {
  if (width > 0 && height > 0) {
    g_surface.width = width;
    g_surface.height = height;
  }
}

void ff7_ios_window_detach(void) {
  g_surface.metal_layer = NULL;
  g_surface.width = 0;
  g_surface.height = 0;
}
