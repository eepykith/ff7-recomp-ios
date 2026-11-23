#include "ff7_host.h"

#include "ff7_platform.h"

#include "../ios/ff7_ios_boot.h"

#include <stdio.h>
#include <string.h>

/* Strong definition lives in ff7_core when FF7_BUNDLE_GAME; otherwise the weak
 * stub in ff7_ios_boot.c. */
extern int ff7_boot_and_run(const char *game_dir);

static ff7_host_config g_config;
static ff7_host_state g_state;
static char g_message[256];
static char g_documents[512];
static char g_support[512];
static int g_inited;

static void set_message(const char *msg) {
  snprintf(g_message, sizeof(g_message), "%s", msg ? msg : "");
}

const char *ff7_host_version(void) {
  return "0.2.0-p1";
}

ff7_host_status ff7_host_init(const ff7_host_config *config) {
  memset(&g_state, 0, sizeof(g_state));
  set_message("");
  if (!config || config->width <= 0 || config->height <= 0) {
    g_state.status = FF7_HOST_ERR_INIT;
    set_message("invalid host config");
    return g_state.status;
  }
  g_config = *config;
  if (g_config.target_fps != 30 && g_config.target_fps != 60) {
    g_config.target_fps = 60;
  }
  g_inited = 1;
  g_state.status = FF7_HOST_OK;
  snprintf(g_message, sizeof(g_message),
           "host ready (%dx%d @ %d FPS, metal=%d)", g_config.width,
           g_config.height, g_config.target_fps, g_config.metal);
  return FF7_HOST_OK;
}

void ff7_host_shutdown(void) {
  memset(&g_state, 0, sizeof(g_state));
  memset(&g_config, 0, sizeof(g_config));
  set_message("");
  ff7_engine_set_drawing(0);
  g_inited = 0;
}

ff7_host_state ff7_host_get_state(void) {
  return g_state;
}

const char *ff7_host_message(void) {
  return g_message;
}

ff7_host_status ff7_host_boot(const char *package_path_or_null) {
  if (!g_inited) {
    g_state.status = FF7_HOST_ERR_INIT;
    set_message("host not initialized");
    return g_state.status;
  }

  /* P0: no real lift/FFNx. A missing package is the expected path. */
  if (package_path_or_null == NULL || package_path_or_null[0] == '\0') {
    g_state.booted = 0;
    g_state.status = FF7_HOST_ERR_NO_GAME;
    set_message(
        "no game package — build one with ff7recomp-mac, then import it");
    return g_state.status;
  }

#if defined(FF7_BUNDLE_GAME) && FF7_BUNDLE_GAME
  {
    int start = ff7_ios_start_game_thread(package_path_or_null);
    if (start < 0) {
      g_state.booted = 0;
      g_state.status = FF7_HOST_ERR_INIT;
      snprintf(g_message, sizeof(g_message),
               "failed to start game thread (%d)", start);
      return g_state.status;
    }
    g_state.booted = 1;
    g_state.status = FF7_HOST_OK;
    snprintf(g_message, sizeof(g_message),
             "ff7_boot_and_run on 64 MB game thread (%s)",
             package_path_or_null);
    return g_state.status;
  }
#else
  /* Surface can present. The lifted game and FFNx are not in this binary. */
  (void)ff7_boot_and_run;
  g_state.booted = 0;
  g_state.status = FF7_HOST_ERR_UNSUPPORTED;
  snprintf(g_message, sizeof(g_message),
           "Metal surface ready; FFNx is not linked (P1). Package: %s",
           package_path_or_null);
  return g_state.status;
#endif
}

void ff7_host_note_present(void) {
  if (g_inited) {
    g_state.frame += 1;
  }
}

ff7_host_status ff7_host_frame(void) {
  if (!g_inited) {
    return FF7_HOST_ERR_INIT;
  }
  if (!g_state.booted) {
    return g_state.status == FF7_HOST_OK ? FF7_HOST_ERR_NO_GAME : g_state.status;
  }
  ff7_host_note_present();
  return FF7_HOST_OK;
}

void ff7_host_set_paths(const char *documents, const char *support) {
  if (documents) {
    snprintf(g_documents, sizeof(g_documents), "%s", documents);
  }
  if (support) {
    snprintf(g_support, sizeof(g_support), "%s", support);
  }
}
