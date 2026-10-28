// PCM output for Puffer's Sendspin player: a ring buffer of 16-bit frames played by miniaudio, with the position and time of the last frame handed to the device, so playback can be scheduled against a clock.
#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// Opens the default output device. Returns 0 on success.
FFI_PLUGIN_EXPORT int pcm_open(int sample_rate, int channels, int capacity_frames);
FFI_PLUGIN_EXPORT void pcm_close(void);

// Appends interleaved frames; returns how many fit.
FFI_PLUGIN_EXPORT int pcm_write(const int16_t* frames, int count);

// Ring positions, in frames since pcm_open.
FFI_PLUGIN_EXPORT int64_t pcm_write_position(void);
FFI_PLUGIN_EXPORT int64_t pcm_read_position(void);

// Drops every buffered frame.
FFI_PLUGIN_EXPORT void pcm_clear(void);

// The ring position the device read at the start of its last callback, and when (pcm_now_ns clock). Returns 0 before the first callback.
FFI_PLUGIN_EXPORT int pcm_last_callback(int64_t* position, int64_t* at_ns);

// Frames between the device reading a frame and the frame leaving the speaker, as reported by the backend.
FFI_PLUGIN_EXPORT int pcm_latency_frames(void);

FFI_PLUGIN_EXPORT void pcm_set_volume(float amplitude);

// A monotonic clock in nanoseconds.
FFI_PLUGIN_EXPORT int64_t pcm_now_ns(void);
