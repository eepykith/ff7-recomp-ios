#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Bookkeeping for the CAMetalLayer created by FF7MetalView.
 * bgfx reads the layer through ff7_platform_window(). */

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
