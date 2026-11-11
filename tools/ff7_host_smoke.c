#include "ff7_host.h"
#include "ff7_ios_window.h"
#include "ff7_platform.h"

#include <stdio.h>
#include <string.h>

static int fail(const char *msg) {
  fprintf(stderr, "smoke: %s\n", msg);
  return 1;
}

int main(void) {
  ff7_host_config cfg = {
      .width = 1280,
      .height = 720,
      .target_fps = 60,
      .metal = 1,
  };

  if (ff7_host_init(&cfg) != FF7_HOST_OK) {
    return fail(ff7_host_message());
  }
  if (strstr(ff7_host_version(), "p1") == NULL) {
    return fail("version should be p1");
  }
  printf("version=%s\n", ff7_host_version());

  /* Same pointer the Metal view will publish for bgfx. */
  char layer_sentinel;
  ff7_platform_set_window(&layer_sentinel, 1920, 1080);
  int w = 0, h = 0;
  void *window = ff7_platform_window(&w, &h);
  if (window != &layer_sentinel || w != 1920 || h != 1080) {
    return fail("platform window mismatch");
  }
  if (ff7_platform_companion_window(&w, &h) != NULL) {
    return fail("companion window should be empty on iOS P1");
  }

  ff7_platform_set_pad(FF7_PAD_A | FF7_PAD_DPAD_UP, 0, 0, 0, 32767, 0, 0);
  ff7_pad_state pad;
  if (!ff7_platform_pad_state(0, &pad)) {
    return fail("pad 0 should be connected");
  }
  if (pad.buttons != (FF7_PAD_A | FF7_PAD_DPAD_UP) || pad.ly != 32767) {
    return fail("pad state mismatch");
  }
  if (ff7_platform_pad_state(1, &pad)) {
    return fail("pad 1 should be absent");
  }
  unsigned char keys[256];
  if (ff7_platform_keyboard_state(keys) != 0 || keys[0] != 0) {
    return fail("keyboard should be idle");
  }

  if (ff7_host_boot(NULL) != FF7_HOST_ERR_NO_GAME) {
    return fail("expected NO_GAME");
  }
  float r = 0, g = 0, b = 0, a = 0;
  ff7_platform_clear_color(&r, &g, &b, &a);
  if (!(r > b)) {
    fprintf(stderr, "clear rgb=%f %f %f\n", r, g, b);
    return fail("no-game clear should be warm");
  }

  if (ff7_host_boot("/tmp/example.ff7pkg") != FF7_HOST_ERR_UNSUPPORTED) {
    return fail("expected UNSUPPORTED without FFNx");
  }
  if (strstr(ff7_host_message(), "FFNx") == NULL) {
    return fail(ff7_host_message());
  }
  ff7_platform_clear_color(&r, &g, &b, &a);
  if (!(b > r)) {
    fprintf(stderr, "clear rgb=%f %f %f\n", r, g, b);
    return fail("waiting clear should be blue");
  }
  if (ff7_engine_owns_present()) {
    return fail("engine should not own the drawable yet");
  }

  ff7_platform_note_present();
  ff7_platform_note_present();
  if (ff7_host_get_state().frame != 2) {
    return fail("present count");
  }

  ff7_ios_window_detach();
  if (ff7_platform_window(NULL, NULL) != NULL) {
    return fail("detach should clear the layer");
  }

  ff7_host_shutdown();
  printf("smoke ok\n");
  return 0;
}
