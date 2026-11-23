// FFNx Renderer backend selectors for builds without FFmpeg (Darwin Metal host).
//
// Upstream these live in FFNx video/ntscj.cpp, which the Android core only compiles when
// FFmpeg is built. Without them the post pass never switches to the POSTPROCESSING program,
// so FFNx's final blit lands in its offscreen framebuffer and nothing is ever drawn to the
// CAMetalLayer (bgfx never asks for a drawable). With FFmpeg off, ntscj_get_overall_color_gamut
// is sRGB, but keep the NTSC-J branch so a toml override still picks a valid program.
//
// Added to the ffnx target by tools/apply_metal_overlay.sh (APPLE AND NOT FF7_HAVE_FFMPEG).
#include "renderer.h"

void Renderer::setPostprocessingBackend()
{
    backendProgram = internalState.bIsOverallColorGamut == COLORGAMUT_NTSCJ
        ? RendererProgram::POSTPROCESSING_NTSCJ
        : RendererProgram::POSTPROCESSING;
}

void Renderer::setYUVMovieBackend()
{
    backendProgram = internalState.bIsOverallColorGamut == COLORGAMUT_NTSCJ
        ? RendererProgram::YUVMOVIE_TRUECOLOR
        : RendererProgram::YUVMOVIE;
}
