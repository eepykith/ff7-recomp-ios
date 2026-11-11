#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Shared host API for Android JNI and iOS Swift/ObjC++ bridges.
 * P0: stubs only. Real FFNx/Metal wiring lands in P1. */

typedef struct ff7_host_config {
  int width;
  int height;
  int target_fps; /* 30 or 60 for MVP */
  int metal;      /* 1 on iOS/macOS, 0 elsewhere */
} ff7_host_config;

typedef enum ff7_host_status {
  FF7_HOST_OK = 0,
  FF7_HOST_ERR_INIT = 1,
  FF7_HOST_ERR_NO_GAME = 2,
  FF7_HOST_ERR_PACKAGE = 3,
  FF7_HOST_ERR_UNSUPPORTED = 4,
} ff7_host_status;

typedef struct ff7_host_state {
  int status; /* ff7_host_status */
  int booted;
  int frame;
} ff7_host_state;

const char *ff7_host_version(void);

ff7_host_status ff7_host_init(const ff7_host_config *config);
void ff7_host_shutdown(void);

/* Snapshot of numeric state. Message is owned by the host until the next call. */
ff7_host_state ff7_host_get_state(void);
const char *ff7_host_message(void);

/* Attempt to boot. Without a bundled/imported game package this returns
 * FF7_HOST_ERR_NO_GAME and leaves a human-readable message. */
ff7_host_status ff7_host_boot(const char *package_path_or_null);

/* Advance one frame of the stub host (no GPU work in P0). */
ff7_host_status ff7_host_frame(void);

/* Paths the launcher uses for Documents / Application Support. */
void ff7_host_set_paths(const char *documents, const char *support);

#ifdef __cplusplus
}
#endif
