#include "ff7_ios_boot.h"

#include "ff7_platform.h"

#include <pthread.h>
#include <stdio.h>
#include <string.h>

#if defined(FF7_BUNDLE_GAME) && FF7_BUNDLE_GAME
extern int ff7_boot_and_run(const char *game_dir);
#else
/* Weak stub so the host links without FFNx. */
__attribute__((weak)) int ff7_boot_and_run(const char *game_dir) {
  (void)game_dir;
  return -1;
}
#endif

static pthread_mutex_t g_boot_mu = PTHREAD_MUTEX_INITIALIZER;
static int g_started;
static char g_game_dir[1024];

static void *ff7_game_thread(void *arg) {
  (void)arg;
  const char *dir = g_game_dir[0] ? g_game_dir : NULL;
  int rc = ff7_boot_and_run(dir);
  fprintf(stderr, "[ff7] game thread finished with %d\n", rc);
  ff7_engine_set_drawing(0);
  return NULL;
}

int ff7_ios_start_game_thread(const char *game_dir) {
  pthread_mutex_lock(&g_boot_mu);
  if (g_started) {
    pthread_mutex_unlock(&g_boot_mu);
    return 1;
  }
#if !defined(FF7_BUNDLE_GAME) || !FF7_BUNDLE_GAME
  pthread_mutex_unlock(&g_boot_mu);
  return -1;
#endif
  if (game_dir && game_dir[0]) {
    snprintf(g_game_dir, sizeof(g_game_dir), "%s", game_dir);
  } else {
    g_game_dir[0] = '\0';
  }

  /* Same as Android GameActivity: deep host stack for lifted recursion. */
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 64u << 20);
  pthread_t thread;
  int err = pthread_create(&thread, &attr, ff7_game_thread, NULL);
  pthread_attr_destroy(&attr);
  if (err != 0) {
    pthread_mutex_unlock(&g_boot_mu);
    return -2;
  }
  pthread_detach(thread);
  g_started = 1;
  ff7_engine_set_drawing(1);
  pthread_mutex_unlock(&g_boot_mu);
  return 0;
}

int ff7_ios_game_thread_started(void) {
  pthread_mutex_lock(&g_boot_mu);
  int started = g_started;
  pthread_mutex_unlock(&g_boot_mu);
  return started;
}
