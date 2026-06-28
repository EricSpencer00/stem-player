//! Live four-stem playback for the desktop app via cpal. The audio callback
//! mixes the four stems by their effective gain and advances a shared transport
//! position. The mix itself is a pure function so it is unit-tested without an
//! audio device.

use std::sync::{Arc, Mutex};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

/// Shared state read by the audio callback.
pub struct Shared {
    pub stems: [Vec<f32>; 4],
    pub gains: [f32; 4],
    pub pos: usize,
    pub playing: bool,
    pub sample_rate: u32,
}

impl Default for Shared {
    fn default() -> Self {
        Shared {
            stems: [Vec::new(), Vec::new(), Vec::new(), Vec::new()],
            gains: [0.8; 4],
            pos: 0,
            playing: false,
            sample_rate: 44100,
        }
    }
}

impl Shared {
    fn len(&self) -> usize {
        self.stems.iter().map(|s| s.len()).max().unwrap_or(0)
    }
}

/// Pure mixer: one output sample summed across the four stems at `pos`, clamped.
/// Extracted so the mixing math is testable without an audio device.
pub fn mix_at(stems: &[Vec<f32>; 4], gains: &[f32; 4], pos: usize) -> f32 {
    let mut acc = 0.0f32;
    for k in 0..4 {
        if pos < stems[k].len() {
            acc += stems[k][pos] * gains[k];
        }
    }
    acc.clamp(-1.0, 1.0)
}

/// Owns the cpal stream; keep it alive to keep audio running.
pub struct AudioOutput {
    pub shared: Arc<Mutex<Shared>>,
    _stream: cpal::Stream,
    out_channels: usize,
}

impl AudioOutput {
    pub fn new() -> Result<Self, String> {
        let host = cpal::default_host();
        let device = host.default_output_device().ok_or("no output device")?;
        let config = device.default_output_config().map_err(|e| e.to_string())?;
        let out_channels = config.channels() as usize;
        let device_sr = config.sample_rate().0;

        let shared = Arc::new(Mutex::new(Shared { sample_rate: device_sr, ..Default::default() }));
        let cb_shared = shared.clone();

        let stream = device
            .build_output_stream(
                &config.into(),
                move |data: &mut [f32], _| {
                    let mut s = cb_shared.lock().unwrap();
                    let len = s.len();
                    for frame in data.chunks_mut(out_channels) {
                        let sample = if s.playing && s.pos < len {
                            let v = mix_at(&s.stems, &s.gains, s.pos);
                            s.pos += 1;
                            v
                        } else {
                            if s.playing && s.pos >= len {
                                s.playing = false;
                            }
                            0.0
                        };
                        for out in frame.iter_mut() {
                            *out = sample;
                        }
                    }
                },
                move |err| eprintln!("audio stream error: {err}"),
                None,
            )
            .map_err(|e| e.to_string())?;
        stream.play().map_err(|e| e.to_string())?;

        Ok(AudioOutput { shared, _stream: stream, out_channels })
    }

    pub fn load(&self, stems: [Vec<f32>; 4]) {
        let mut s = self.shared.lock().unwrap();
        s.stems = stems;
        s.pos = 0;
        s.playing = false;
    }

    pub fn set_gains(&self, gains: [f32; 4]) {
        self.shared.lock().unwrap().gains = gains;
    }

    pub fn toggle_play(&self) {
        let mut s = self.shared.lock().unwrap();
        if s.playing {
            s.playing = false;
        } else {
            if s.pos >= s.len() {
                s.pos = 0;
            }
            s.playing = true;
        }
    }

    pub fn stop(&self) {
        let mut s = self.shared.lock().unwrap();
        s.playing = false;
        s.pos = 0;
    }

    pub fn is_playing(&self) -> bool {
        self.shared.lock().unwrap().playing
    }

    #[allow(dead_code)]
    pub fn channels(&self) -> usize {
        self.out_channels
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mix_sums_stems_with_gain_and_clamps() {
        let stems = [vec![0.5, 0.0], vec![0.5, 0.0], vec![0.5, 0.0], vec![0.5, 2.0]];
        // pos 0: 0.5*0.8*4 = 1.6 → clamps to 1.0
        assert_eq!(mix_at(&stems, &[0.8; 4], 0), 1.0);
        // muted-ish gains: only last stem audible at pos 1 (2.0*1.0) → clamps 1.0
        assert_eq!(mix_at(&stems, &[0.0, 0.0, 0.0, 1.0], 1), 1.0);
        // past end of a stem contributes nothing
        let s2 = [vec![0.3], vec![], vec![], vec![]];
        assert_eq!(mix_at(&s2, &[1.0; 4], 5), 0.0);
    }

    #[test]
    fn silence_when_all_gains_zero() {
        let stems = [vec![1.0], vec![1.0], vec![1.0], vec![1.0]];
        assert_eq!(mix_at(&stems, &[0.0; 4], 0), 0.0);
    }
}
