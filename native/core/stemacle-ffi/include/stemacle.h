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

/* Compute a cols-bucket peak waveform envelope (0..1) into `out`.
 * O(n) time and O(cols) space — use on iOS instead of stemacle_spectrogram
 * to avoid the large STFT allocation on long tracks. */
void stemacle_waveform_envelope(const float *samples, size_t len, size_t cols,
                                float *out);

/* Compute a cols-bucket peak+RMS waveform envelope into `out`, interleaved as
 * [peak_0, rms_0, peak_1, rms_1, …] (length cols*2). Drives the native
 * two-tone stem lane (RMS body + peak tips) at full scroll-window resolution. */
void stemacle_waveform_peaks_rms(const float *samples, size_t len, size_t cols,
                                 float *out);

/* Number of STFT frames for a signal of `len` samples — the row count to
 * allocate for stemacle_magnitudes and the vocal mask. */
size_t stemacle_frame_count(size_t len);

/* Vocal-mask frequency weight for a bin (0..1). Pure. */
float stemacle_vocal_mask_weight_for_bin(size_t bin);

/* Per-frame magnitude spectra over the first MODEL_BINS (=1024) bins for L and R,
 * row-major (out[f*1024 + b]). Each output buffer must hold
 * stemacle_frame_count(len)*1024 floats. Feeds the iOS Spleeter ONNX model. */
void stemacle_magnitudes(const float *left, const float *right, size_t len,
                         float *out_mag_l, float *out_mag_r);

/* Separate stereo PCM using a caller-supplied vocal mask (mask_len must equal
 * frame_count(len)*1024, row-major, values 0..1). The neural path: mask from the
 * Spleeter ONNX model → identical DSP pipeline → stems. Free via
 * stemacle_stems_free; null on invalid input. */
StemacleStems *stemacle_separate_with_mask(const float *left, const float *right,
                                           size_t len, unsigned int sample_rate,
                                           const float *mask, size_t mask_len);

#ifdef __cplusplus
}
#endif

#endif /* STEMACLE_H */
