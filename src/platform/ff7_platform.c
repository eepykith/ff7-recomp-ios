#include "ff7_platform.h"

#include "ff7_host.h"

#include <pthread.h>
#include <string.h>

static pthread_mutex_t g_win_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_pad_mu = PTHREAD_MUTEX_INITIALIZER;

static void *g_window;
static int g_width;
static int g_height;
static ff7_pad_state g_pad;
static int g_engine_drawing;

void ff7_platform_set_window(void *metal_layer, int width, int height) {
  pthread_mutex_lock(&g_win_mu);
  g_window = metal_layer;
  g_width = width > 0 ? width : 0;
  g_height = height > 0 ? height : 0;
  pthread_mutex_unlock(&g_win_mu);
}

void *ff7_platform_window(int *width, int *height) {
  pthread_mutex_lock(&g_win_mu);
  if (width) {
    *width = g_width;
  }
  if (height) {
    *height = g_height;
  }
  void *window = g_window;
  pthread_mutex_unlock(&g_win_mu);
  return window;
}

void *ff7_platform_companion_window(int *width, int *height) {
  if (width) {
    *width = 0;
  }
  if (height) {
    *height = 0;
  }
  return NULL;
}

int ff7_platform_keyboard_state(unsigned char keys[256]) {
  if (keys) {
    memset(keys, 0, 256);
  }
  return 0;
}

void ff7_platform_set_pad(unsigned short buttons, unsigned char left_trigger,
                          unsigned char right_trigger, short lx, short ly,
                          short rx, short ry) {
  pthread_mutex_lock(&g_pad_mu);
  g_pad.buttons = buttons;
  g_pad.left_trigger = left_trigger;
  g_pad.right_trigger = right_trigger;
  g_pad.lx = lx;
  g_pad.ly = ly;
  g_pad.rx = rx;
  g_pad.ry = ry;
  pthread_mutex_unlock(&g_pad_mu);
}

int ff7_platform_pad_state(unsigned index, ff7_pad_state *out) {
  if (index != 0 || !out) {
    return 0;
  }
  pthread_mutex_lock(&g_pad_mu);
  *out = g_pad;
  pthread_mutex_unlock(&g_pad_mu);
  return 1;
}

void ff7_platform_pad_rumble(unsigned index, unsigned short left,
                             unsigned short right) {
  (void)index;
  (void)left;
  (void)right;
}

void ff7_platform_note_present(void) {
  ff7_host_note_present();
}

void ff7_platform_clear_color(float *r, float *g, float *b, float *a) {
  float cr = 0.02f, cg = 0.02f, cb = 0.025f, ca = 1.f;
  ff7_host_state state = ff7_host_get_state();
  if (state.booted) {
    cr = cg = cb = 0.f;
  } else if (state.status == FF7_HOST_ERR_NO_GAME) {
    /* Warm dark — no package imported. */
    cr = 0.22f;
    cg = 0.08f;
    cb = 0.05f;
  } else if (state.status == FF7_HOST_ERR_UNSUPPORTED ||
             state.status == FF7_HOST_OK) {
    /* Blue — Metal is live, FFNx is not drawing yet. */
    cr = 0.04f;
    cg = 0.10f;
    cb = 0.22f;
  }
  if (r) {
    *r = cr;
  }
  if (g) {
    *g = cg;
  }
  if (b) {
    *b = cb;
  }
  if (a) {
    *a = ca;
  }
}

void ff7_engine_set_drawing(int drawing) {
  g_engine_drawing = drawing ? 1 : 0;
}

int ff7_engine_owns_present(void) {
  return g_engine_drawing;
}
