#include "pcm_player.h"

#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#include "miniaudio.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
#endif

static ma_device device;
static int opened = 0;
static int16_t* ring = NULL;
static int ring_frames = 0;
static int ring_channels = 0;
static _Atomic int64_t write_pos = 0;
static _Atomic int64_t read_pos = 0;
static _Atomic float volume = 1.0f;

// The position and time of the last callback, published with a sequence counter so readers see a consistent pair.
static _Atomic uint32_t callback_seq = 0;
static int64_t callback_position = 0;
static int64_t callback_at = 0;

int64_t pcm_now_ns(void) {
#ifdef __APPLE__
  static mach_timebase_info_data_t timebase;
  if (timebase.denom == 0) mach_timebase_info(&timebase);
  return (int64_t)(mach_absolute_time() * timebase.numer / timebase.denom);
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

static void data_callback(ma_device* dev, void* output, const void* input, ma_uint32 frames) {
  (void)input;
  int16_t* out = (int16_t*)output;
  const int64_t now = pcm_now_ns();
  const int64_t r = atomic_load(&read_pos);
  const int64_t w = atomic_load(&write_pos);
  const int64_t available = w - r;
  const ma_uint32 n = available <= 0 ? 0 : (available < (int64_t)frames ? (ma_uint32)available : frames);
  const float vol = atomic_load(&volume);
  const int ch = ring_channels;

  atomic_fetch_add(&callback_seq, 1);
  callback_position = r;
  callback_at = now;
  atomic_fetch_add(&callback_seq, 1);

  for (ma_uint32 f = 0; f < n; f++) {
    const int16_t* src = ring + ((r + f) % ring_frames) * ch;
    for (int c = 0; c < ch; c++) {
      float v = src[c] * vol;
      out[f * ch + c] = (int16_t)(v > 32767.0f ? 32767.0f : (v < -32768.0f ? -32768.0f : v));
    }
  }
  if (n < frames) memset(out + n * ch, 0, (frames - n) * ch * sizeof(int16_t));
  atomic_store(&read_pos, r + n);
  (void)dev;
}

int pcm_open(int sample_rate, int channels, int capacity_frames) {
  pcm_close();
  ring = (int16_t*)calloc((size_t)capacity_frames * channels, sizeof(int16_t));
  if (ring == NULL) return -1;
  ring_frames = capacity_frames;
  ring_channels = channels;
  atomic_store(&write_pos, 0);
  atomic_store(&read_pos, 0);
  callback_position = 0;
  callback_at = 0;

  ma_device_config config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_s16;
  config.playback.channels = (ma_uint32)channels;
  config.sampleRate = (ma_uint32)sample_rate;
  config.dataCallback = data_callback;
  config.performanceProfile = ma_performance_profile_low_latency;
  if (ma_device_init(NULL, &config, &device) != MA_SUCCESS) {
    free(ring);
    ring = NULL;
    return -2;
  }
  if (ma_device_start(&device) != MA_SUCCESS) {
    ma_device_uninit(&device);
    free(ring);
    ring = NULL;
    return -3;
  }
  opened = 1;
  return 0;
}

void pcm_close(void) {
  if (opened) {
    ma_device_uninit(&device);
    opened = 0;
  }
  free(ring);
  ring = NULL;
}

int pcm_write(const int16_t* frames, int count) {
  if (ring == NULL) return 0;
  const int64_t w = atomic_load(&write_pos);
  const int64_t r = atomic_load(&read_pos);
  int free_frames = ring_frames - (int)(w - r);
  if (count > free_frames) count = free_frames;
  for (int f = 0; f < count; f++) {
    memcpy(ring + ((w + f) % ring_frames) * ring_channels, frames + f * ring_channels, ring_channels * sizeof(int16_t));
  }
  atomic_store(&write_pos, w + count);
  return count;
}

int64_t pcm_write_position(void) { return atomic_load(&write_pos); }

int64_t pcm_read_position(void) { return atomic_load(&read_pos); }

void pcm_clear(void) { atomic_store(&write_pos, atomic_load(&read_pos)); }

int pcm_last_callback(int64_t* position, int64_t* at_ns) {
  uint32_t before, after;
  do {
    before = atomic_load(&callback_seq);
    *position = callback_position;
    *at_ns = callback_at;
    after = atomic_load(&callback_seq);
  } while (before != after || (before & 1));
  return *at_ns != 0;
}

int pcm_latency_frames(void) {
  if (!opened) return 0;
  return (int)(device.playback.internalPeriodSizeInFrames * device.playback.internalPeriods);
}

void pcm_set_volume(float amplitude) { atomic_store(&volume, amplitude); }
