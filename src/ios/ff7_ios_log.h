#pragma once
/* The engine's log on the phone: everything the engine and FFNx write to stderr and stdout
 * (the crash handler's report, mod loading, sound and file errors) is copied into
 * <dir>/engine.log, as the core's Android app passes it to the system log. The last session's log is
 * kept as engine.prev.log, so a crash's report survives the relaunch. The output still reaches
 * the original stderr (the Xcode console, simctl --console-pty). */
#ifdef __cplusplus
extern "C" {
#endif

/* Start once, as early as possible (AppDelegate). 0 on success. */
int ff7_ios_log_start(const char *dir);

#ifdef __cplusplus
}
#endif
