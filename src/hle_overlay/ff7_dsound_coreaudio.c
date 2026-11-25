/*
 * ff7_dsound_coreaudio.c - the Apple output of the DirectSound HLE mixer (ff7_dsound.c).
 *
 * Android plays the mixer through an AAudio stream; on macOS and iOS this opens the default
 * output Audio Unit (RemoteIO on iOS) as 48 kHz stereo float and calls the same mix function
 * from its render callback. Added to ff7_core on Apple by tools/apply_metal_overlay.sh
 * (FF7_IOS_DSOUND_COREAUDIO), which also points ff7_dsound.c's mixer_start here.
 *
 * Kept apart from ff7_dsound.c so the CoreAudio headers (CoreFoundation types) never meet the
 * Win32 HLE headers.
 *
 * FF7_DSOUND_STATS=1 logs callbacks, frames and the peak level every 5 s; without it the
 * first audible buffer is still logged once ("[dsound] CoreAudio: first non-silent buffer").
 */
#if defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>
#include <TargetConditionals.h>
#include <math.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef void (*ff7_mix_fn)(float *out, int32_t frames);

static AudioComponentInstance g_unit;
static ff7_mix_fn g_mix;
static int g_rate;
static int g_stats;
static atomic_uint_fast64_t g_callbacks, g_frames, g_loud_frames;
static atomic_int g_first_loud;
static float g_peak;          /* render thread only */
static uint64_t g_next_report;

static OSStatus render_cb(void *user, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                          UInt32 bus, UInt32 frames, AudioBufferList *io) {
    (void)user; (void)ts; (void)bus;
    if (!io || io->mNumberBuffers < 1 || !io->mBuffers[0].mData) return noErr;
    float *out = (float *)io->mBuffers[0].mData;
    UInt32 cap = io->mBuffers[0].mDataByteSize / (UInt32)(2 * sizeof(float));
    if (frames > cap) frames = cap;
    g_mix(out, (int32_t)frames);

    float peak = 0.0f;
    for (UInt32 i = 0; i < 2 * frames; i++) { float a = fabsf(out[i]); if (a > peak) peak = a; }
    uint64_t total = atomic_fetch_add(&g_frames, frames) + frames;
    atomic_fetch_add(&g_callbacks, 1);
    if (peak > 1e-4f) {
        atomic_fetch_add(&g_loud_frames, frames);
        if (!atomic_exchange(&g_first_loud, 1))
            fprintf(stderr, "[dsound] CoreAudio: first non-silent buffer (peak %.3f) after %llu frames\n",
                    peak, (unsigned long long)total);
    } else if (flags) {
        *flags |= kAudioUnitRenderAction_OutputIsSilence;
    }
    if (peak > g_peak) g_peak = peak;
    if (g_stats && total >= g_next_report) {
        g_next_report = total + (uint64_t)g_rate * 5;
        fprintf(stderr, "[dsound] CoreAudio: %llu callbacks, %llu frames, %llu non-silent, peak %.3f\n",
                (unsigned long long)atomic_load(&g_callbacks), (unsigned long long)total,
                (unsigned long long)atomic_load(&g_loud_frames), g_peak);
        g_peak = 0.0f;
    }
    return noErr;
}

#define CHECK(call, what) do { OSStatus e_ = (call); if (e_ != noErr) { \
    fprintf(stderr, "[dsound] CoreAudio %s failed: %d\n", what, (int)e_); goto fail; } } while (0)

/* Start the output; mix fills `frames` interleaved stereo float frames at `rate` Hz.
 * Returns 0 on success, -1 when no output could be opened. */
int ff7_apple_audio_start(int rate, ff7_mix_fn mix) {
    if (g_unit) return 0;
    g_mix = mix;
    g_rate = rate;
    g_stats = getenv("FF7_DSOUND_STATS") != NULL;
    g_next_report = (uint64_t)rate * 5;

    AudioComponentDescription d = {0};
    d.componentType = kAudioUnitType_Output;
#if TARGET_OS_IPHONE
    d.componentSubType = kAudioUnitSubType_RemoteIO;
#else
    d.componentSubType = kAudioUnitSubType_DefaultOutput;
#endif
    d.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent comp = AudioComponentFindNext(NULL, &d);
    if (!comp) { fprintf(stderr, "[dsound] CoreAudio: no output unit\n"); return -1; }
    CHECK(AudioComponentInstanceNew(comp, &g_unit), "AudioComponentInstanceNew");

    AudioStreamBasicDescription f = {0};
    f.mSampleRate = rate;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    f.mChannelsPerFrame = 2;
    f.mBitsPerChannel = 32;
    f.mFramesPerPacket = 1;
    f.mBytesPerFrame = 2 * sizeof(float);
    f.mBytesPerPacket = f.mBytesPerFrame;
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                               &f, sizeof f), "StreamFormat");

    AURenderCallbackStruct cb = { render_cb, NULL };
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                               &cb, sizeof cb), "SetRenderCallback");
    CHECK(AudioUnitInitialize(g_unit), "AudioUnitInitialize");
    CHECK(AudioOutputUnitStart(g_unit), "AudioOutputUnitStart");
    fprintf(stderr, "[dsound] mixer: CoreAudio %d Hz stereo float\n", rate);
    return 0;

fail:
    if (g_unit) { AudioComponentInstanceDispose(g_unit); g_unit = NULL; }
    return -1;
}

/* Stop the output while the game is paused (ff7_platform_set_paused) and start it again; a
 * call also stops RemoteIO, and the start afterwards brings it back. */
void ff7_apple_audio_pause(int paused) {
    if (!g_unit) return;
    OSStatus e = paused ? AudioOutputUnitStop(g_unit) : AudioOutputUnitStart(g_unit);
    if (e != noErr) fprintf(stderr, "[dsound] CoreAudio %s failed: %d\n", paused ? "stop" : "start", (int)e);
    else fprintf(stderr, "[dsound] CoreAudio %s\n", paused ? "paused" : "resumed");
}
#endif
