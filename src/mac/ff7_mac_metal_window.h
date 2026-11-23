#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Create an AppKit window hosting a CAMetalLayer and publish it via
 * ff7_platform_set_window. Returns 0 on success. */
int ff7_mac_metal_window_create(int width, int height);

/* Drain AppKit events so the window stays responsive while the game runs. */
void ff7_mac_metal_window_pump(void);

#ifdef __cplusplus
}
#endif
