#include "ff7_ios_log.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* Past this the log stops growing (a runaway trace must not fill the phone); the end of a
 * session, a crash report, is what matters most, so the file then keeps its last part. */
#define LOG_CAP (16u << 20)

static int g_file = -1, g_console = -1, g_pipe_read = -1;
static char g_path[1024];
static size_t g_size;

static void write_all(int fd, const char *p, size_t n) {
  while (n > 0) {
    ssize_t w = write(fd, p, n);
    if (w < 0) {
      if (errno == EINTR) continue;
      return;
    }
    p += w;
    n -= (size_t)w;
  }
}

/* The log is full: keep its second half and go on after it. */
static void trim(void) {
  off_t keep = (off_t)(LOG_CAP / 2);
  char *buf = malloc((size_t)keep);
  if (!buf) return;
  ssize_t got = pread(g_file, buf, (size_t)keep, (off_t)g_size - keep);
  if (got > 0 && ftruncate(g_file, 0) == 0) {
    const char *note = "[log] ... earlier output dropped (the log is kept under 16 MB) ...\n";
    lseek(g_file, 0, SEEK_SET);
    write_all(g_file, note, strlen(note));
    write_all(g_file, buf, (size_t)got);
    g_size = strlen(note) + (size_t)got;
  }
  free(buf);
}

static void *pump(void *arg) {
  (void)arg;
  char buf[16384];
  for (;;) {
    ssize_t n = read(g_pipe_read, buf, sizeof buf);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) break;
    if (g_console >= 0) write_all(g_console, buf, (size_t)n);
    if (g_size + (size_t)n > LOG_CAP) trim();
    write_all(g_file, buf, (size_t)n);   /* plain write(): in the kernel at once, kept if the app dies */
    g_size += (size_t)n;
  }
  return NULL;
}

int ff7_ios_log_start(const char *dir) {
  static int started;
  if (started || !dir) return started ? 0 : -1;
  char prev[1100];
  snprintf(g_path, sizeof g_path, "%s/engine.log", dir);
  snprintf(prev, sizeof prev, "%s/engine.prev.log", dir);
  mkdir(dir, 0755);
  rename(g_path, prev);                  /* the last session's log, crash report included */
  g_file = open(g_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (g_file < 0) return -1;

  int p[2];
  if (pipe(p) != 0) { close(g_file); g_file = -1; return -1; }
  g_console = dup(STDERR_FILENO);
  g_pipe_read = p[0];
  fflush(stdout);
  fflush(stderr);
  dup2(p[1], STDERR_FILENO);
  dup2(p[1], STDOUT_FILENO);
  close(p[1]);
  setvbuf(stdout, NULL, _IOLBF, 0);     /* stdout is a pipe now: flush it line by line */

  pthread_t t;
  pthread_attr_t a;
  pthread_attr_init(&a);
  pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
  if (pthread_create(&t, &a, pump, NULL) != 0) {
    pthread_attr_destroy(&a);
    dup2(g_console, STDERR_FILENO);
    return -1;
  }
  pthread_attr_destroy(&a);
  started = 1;

  time_t now = time(NULL);
  char when[64];
  strftime(when, sizeof when, "%Y-%m-%d %H:%M:%S", localtime(&now));
  fprintf(stderr, "[log] FF7Recomp engine log, started %s\n", when);
  return 0;
}
