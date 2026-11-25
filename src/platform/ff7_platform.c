#include "ff7_platform.h"

#include "ff7_host.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static pthread_mutex_t g_win_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_pad_mu = PTHREAD_MUTEX_INITIALIZER;

static void *g_window;
static int g_width;
static int g_height;
static ff7_pad_state g_pad;
static unsigned short g_inject;
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

/* The game reads the pad once per game frame (30 a second in the field, as few as 15 in
 * battle), so a press and release between two reads would be lost, and two quick taps would
 * merge. What the game sees (g_pad.buttons) therefore follows the live buttons with these
 * rules, at no cost in latency:
 *   - a press shows at once;
 *   - a press stays shown until a game frame has passed (ff7_platform_pad_frame, called by the
 *     engine each game frame), so even the shortest tap is read;
 *   - a press that comes while the button is still shown from the last one waits, and the
 *     next frame shows the button released first, so every tap is a separate press.
 * When no game frames come (the engine not running yet), releases show at once. */
static unsigned short g_live;          /* what the fingers and the controller hold now */
static unsigned short g_seen;          /* shown across a game frame: may be released at once */
static unsigned short g_gap;           /* held released this frame between two taps */
static unsigned char g_pending[16];    /* taps waiting for their own frame */
static struct timespec g_last_frame;

static int frames_running(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  double dt = (double)(now.tv_sec - g_last_frame.tv_sec) +
              (double)(now.tv_nsec - g_last_frame.tv_nsec) / 1e9;
  return g_last_frame.tv_sec != 0 && dt < 0.25;
}

void ff7_platform_set_pad(unsigned short buttons, unsigned char left_trigger,
                          unsigned char right_trigger, short lx, short ly,
                          short rx, short ry) {
  pthread_mutex_lock(&g_pad_mu);
  unsigned short rising = buttons & (unsigned short)~g_live;
  unsigned short falling = g_live & (unsigned short)~buttons;
  int running = frames_running();
  g_live = buttons;
  for (int bit = 0; bit < 16; bit++) {
    unsigned short m = (unsigned short)(1u << bit);
    if (rising & m) {
      if (!running || (!(g_pad.buttons & m) && !(g_gap & m))) {
        g_pad.buttons |= m;
        g_seen &= (unsigned short)~m;
      } else if (g_pending[bit] < 8) {
        g_pending[bit]++;
      }
    }
    if ((falling & m) && (!running || ((g_seen & m) && g_pending[bit] == 0))) {
      g_pad.buttons &= (unsigned short)~m;
    }
  }
  g_pad.left_trigger = left_trigger;
  g_pad.right_trigger = right_trigger;
  g_pad.lx = lx;
  g_pad.ly = ly;
  g_pad.rx = rx;
  g_pad.ry = ry;
  pthread_mutex_unlock(&g_pad_mu);
}

/* Pause: the app left the screen or a call took the audio. The game thread waits at its next
 * frame (so it never draws while the app is in the background, which iOS forbids) and both
 * sound outputs stop: the game's mixer (CoreAudio) and FFNx's music and voices (miniaudio,
 * which a call stops and never starts again by itself). */
/* Defaults for the launcher alone (no game linked); the core's own (ff7_dsound_coreaudio.c,
 * soloud_miniaudio.cpp) take their place in the full app. */
__attribute__((weak)) void ff7_apple_audio_pause(int paused) { (void)paused; }
__attribute__((weak)) void ff7_soloud_pause(int paused) { (void)paused; }
static pthread_mutex_t g_pause_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_pause_cv = PTHREAD_COND_INITIALIZER;
static int g_paused;

void ff7_platform_set_paused(int paused) {
  pthread_mutex_lock(&g_pause_mu);
  int changed = (paused != 0) != (g_paused != 0);
  g_paused = paused != 0;
  if (changed) {
    ff7_apple_audio_pause(g_paused);
    ff7_soloud_pause(g_paused);
  }
  pthread_cond_broadcast(&g_pause_cv);
  pthread_mutex_unlock(&g_pause_mu);
}

int ff7_platform_paused(void) {
  pthread_mutex_lock(&g_pause_mu);
  int paused = g_paused;
  pthread_mutex_unlock(&g_pause_mu);
  return paused;
}

static void wait_while_paused(void) {
  pthread_mutex_lock(&g_pause_mu);
  while (g_paused) pthread_cond_wait(&g_pause_cv, &g_pause_mu);
  pthread_mutex_unlock(&g_pause_mu);
}

/* Once per game frame, on the game thread (FF7_IOS_PAD_FRAME in companion.cpp). */
/* FF7_FPS_STATS=1: game frames per second in the log every 5 s (the frame rate setting). */
static void count_frame(void) {
  static int on = -1;
  static struct timespec start;
  static unsigned frames;
  if (on < 0) on = getenv("FF7_FPS_STATS") != NULL;
  if (!on) return;
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  if (start.tv_sec == 0) start = now;
  frames++;
  double dt = (double)(now.tv_sec - start.tv_sec) + (double)(now.tv_nsec - start.tv_nsec) / 1e9;
  if (dt >= 5.0) {
    fprintf(stderr, "[ff7] %.1f game frames/s\n", frames / dt);
    frames = 0;
    start = now;
  }
}

void ff7_platform_pad_frame(void) {
  wait_while_paused();
  count_frame();
  pthread_mutex_lock(&g_pad_mu);
  clock_gettime(CLOCK_MONOTONIC, &g_last_frame);
  unsigned short prev = g_pad.buttons, next = 0;
  g_gap = 0;
  for (int bit = 0; bit < 16; bit++) {
    unsigned short m = (unsigned short)(1u << bit);
    if (g_pending[bit] > 0) {
      if (prev & m) {
        g_gap |= m;                     /* a released frame, then the next tap */
      } else {
        next |= m;
        g_pending[bit]--;
      }
    } else if (g_live & m) {
      next |= m;
    }
  }
  g_seen = prev & next;
  g_pad.buttons = next;
  pthread_mutex_unlock(&g_pad_mu);
}

int ff7_platform_pad_state(unsigned index, ff7_pad_state *out) {
  if (index != 0 || !out) {
    return 0;
  }
  pthread_mutex_lock(&g_pad_mu);
  *out = g_pad;
  out->buttons |= g_inject;
  pthread_mutex_unlock(&g_pad_mu);
  return 1;
}

/* Same contract as the Android host: the injected mask (quickboot's presses) replaces the
 * previous one and is merged only into what the game reads, so ff7_platform_pad_buttons()
 * keeps reporting the player's own buttons. */
void ff7_platform_pad_inject(unsigned short buttons) {
  pthread_mutex_lock(&g_pad_mu);
  g_inject = buttons;
  pthread_mutex_unlock(&g_pad_mu);
}

int ff7_platform_pad_buttons(void) {
  pthread_mutex_lock(&g_pad_mu);
  int buttons = g_pad.buttons;
  pthread_mutex_unlock(&g_pad_mu);
  return buttons;
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
