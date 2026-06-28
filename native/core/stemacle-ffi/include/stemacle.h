/*
 * stemacle.h — stable C ABI for the Stemacle shared Rust DSP core.
 *
 * Hand-written to mirror stemacle-ffi/src/lib.rs exactly. Imported by the Apple
 * StemacleKit Swift package (module map) and the Slint desktop shell.
 *
 * Ownership: stemacle_separate() allocates a StemacleStems and four PCM buffers;
 * release them with stemacle_stems_free(). All other functions are pure.
 */
#ifndef STEMACLE_H
#define STEMACLE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct StemacleStems {
  float *drums_ptr;
  float *vocals_ptr;
  float *bass_ptr;
  float *melody_ptr;
  size_t len;
  unsigned int sample_rate;
  float bpm;
  float measure_offset;
  float beat_offset;
  float tempo_confidence;
} StemacleStems;

/* Separate stereo PCM into four mono stems. `left`/`right` hold `len` samples
 * (pass the same pointer twice for mono). Returns NULL on invalid input. */
StemacleStems *stemacle_separate(const float *left, const float *right,
                                 size_t len, unsigned int sample_rate);

/* Free a StemacleStems returned by stemacle_separate (NULL is a no-op). */
void stemacle_stems_free(StemacleStems *stems);

/* Snap a transport position up to the next loop-grid boundary. */
float stemacle_snap_loop_end(float bpm, float measure_offset, float beat_offset,
                             float duration, float current_sec,
                             float loop_length);

/* Compute a loop [start, end); writes out params. Returns 1 if the loop fits in
 * the track, 0 if it must be rejected. */
unsigned int stemacle_loop_range(float bpm, float measure_offset,
                                 float beat_offset, float duration,
                                 float current_sec, float loop_length,
                                 float *out_start, float *out_end);

/* Measure length in seconds for a BPM. */
float stemacle_measure_length(float bpm);

/* Fold a transport position into an active loop window (active != 0). */
float stemacle_audible_stem_time(float transport_sec, float loop_start,
                                 float loop_end, unsigned int active,
                                 float duration);

/* Compute a cols×rows log-magnitude spectrogram (0..1) into `out` (length
 * cols*rows, column-major: out[col*rows + row]; row 0 = low frequency). */
void stemacle_spectrogram(const float *samples, size_t len, size_t cols,
                          size_t rows, float *out);

#ifdef __cplusplus
}
#endif

#endif /* STEMACLE_H */
