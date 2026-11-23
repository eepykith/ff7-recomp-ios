// FFNx's FFmpeg movie player for builds without FFmpeg (Darwin Metal hosts).
//
// FFNx video/movies.cpp is only compiled when FFmpeg is built for the target. Without it, FFNx's
// own movies.cpp still calls these. The Mac host linked with -undefined dynamic_lookup, which hid
// them; an iOS app links strictly. Each movie reports itself as finished on its first update
// (ffmpeg_update_movie_sample returns 0), so the game moves on as if it had played.
//
// Added to the ffnx target by tools/apply_metal_overlay.sh (APPLE AND NOT FF7_HAVE_FFMPEG).
#include "video/movies.h"

void ffmpeg_release_movie_objects() {}
uint32_t ffmpeg_prepare_movie(const char *, bool) { return 0; }
uint32_t ffmpeg_prepare_movie_from_io(const char *, void *, int (*)(void *, uint8_t *, int),
                                      int64_t (*)(void *, int64_t, int), void (*)(void *), bool)
{
    return 0;
}
void ffmpeg_stop_movie() {}
uint32_t ffmpeg_update_movie_sample(bool) { return 0; }   // 0 = no more frames: the movie ends
void ffmpeg_draw_current_frame() {}
void ffmpeg_loop() {}
uint32_t ffmpeg_get_movie_frame() { return 0; }
short ffmpeg_get_fps_ratio() { return 1; }
void draw_yuv_frame(uint32_t) {}
