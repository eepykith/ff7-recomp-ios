#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* P1 will create a CAMetalLayer-backed surface for bgfx.
 * P0 only declares the entry points the Swift GameHost will call. */

typedef struct ff7_ios_surface {
  void *metal_layer; /* CAMetalLayer* */
  int width;
  int height;
} ff7_ios_surface;

int ff7_ios_window_attach(ff7_ios_surface *surface);
void ff7_ios_window_resize(int width, int height);
void ff7_ios_window_detach(void);

#ifdef __cplusplus
}
#endif
