#pragma once

/* Platform ABI shared with ff7-recomp-android (src/host/ff7_boot.h).
 * FFNx/bgfx call ff7_platform_window() for the drawable (ANativeWindow on
 * Android, CAMetalLayer on iOS). The iOS view calls the setters. */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
  FF7_PAD_DPAD_UP = 0x0001,
  FF7_PAD_DPAD_DOWN = 0x0002,
  FF7_PAD_DPAD_LEFT = 0x0004,
  FF7_PAD_DPAD_RIGHT = 0x0008,
  FF7_PAD_START = 0x0010,
  FF7_PAD_BACK = 0x0020,
  FF7_PAD_LEFT_SHOULDER = 0x0100,
  FF7_PAD_RIGHT_SHOULDER = 0x0200,
  FF7_PAD_A = 0x1000,
  FF7_PAD_B = 0x2000,
  FF7_PAD_X = 0x4000,
  FF7_PAD_Y = 0x8000
};

typedef struct ff7_pad_state {
  unsigned short buttons;
  unsigned char left_trigger, right_trigger;
  short lx, ly, rx, ry;
} ff7_pad_state;

/* Renderer entry. Returns the CAMetalLayer* (or NULL). */
void *ff7_platform_window(int *width, int *height);
void *ff7_platform_companion_window(int *width, int *height);

/* Called by FF7MetalView when the layer is created, resized, or released. */
void ff7_platform_set_window(void *metal_layer, int width, int height);

int ff7_platform_keyboard_state(unsigned char keys[256]);

int ff7_platform_pad_state(unsigned index, ff7_pad_state *out);
void ff7_platform_set_pad(unsigned short buttons, unsigned char left_trigger,
                          unsigned char right_trigger, short lx, short ly,
                          short rx, short ry);
void ff7_platform_pad_inject(unsigned short buttons);
/* Once per game frame, from the engine: lets short taps reach the game (ff7_platform.c). */
void ff7_platform_pad_frame(void);
/* Pause the game at its next frame and stop its sound (1), or go on (0). Main thread. */
void ff7_platform_set_paused(int paused);
int ff7_platform_paused(void);
int ff7_platform_pad_buttons(void);
void ff7_platform_pad_rumble(unsigned index, unsigned short left,
                             unsigned short right);

/* One presented drawable. Increments the host frame counter. */
void ff7_platform_note_present(void);

/* Clear color while FFNx does not own the drawable. */
void ff7_platform_clear_color(float *r, float *g, float *b, float *a);

/* 1 once a linked ff7_boot_and_run has been started. Metal then stops clearing. */
int ff7_engine_owns_present(void);
void ff7_engine_set_drawing(int drawing);

#ifdef __cplusplus
}
#endif
