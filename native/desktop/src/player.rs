//! Desktop view-model: WAV I/O + the separation/mixing state. This is the
//! cross-platform logic that `cargo test` covers on the dev host — the part of
//! the Windows build we can't smoke-test manually still runs here.

use std::io::{Read, Write};
use std::path::Path;

use stemacle_dsp::{separate, CoherenceSeparator, StemSplit, STEMS};

/// Minimal PCM container: interleaved-free stereo float at a sample rate.
pub struct Pcm {
    pub left: Vec<f32>,
    pub right: Vec<f32>,
    pub sample_rate: u32,
}

/// Read a 16-bit or 32-bit-float PCM WAV into stereo float. Hand-rolled to keep
/// the dependency surface tiny; broader codec support is a documented follow-up.
pub fn read_wav(path: &Path) -> Result<Pcm, String> {
    let mut bytes = Vec::new();
    std::fs::File::open(path)
        .map_err(|e| e.to_string())?
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    parse_wav(&bytes)
}

fn rd_u32(b: &[u8], o: usize) -> u32 {
    u32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]])
}
fn rd_u16(b: &[u8], o: usize) -> u16 {
    u16::from_le_bytes([b[o], b[o + 1]])
}

fn parse_wav(b: &[u8]) -> Result<Pcm, String> {
    if b.len() < 12 || &b[0..4] != b"RIFF" || &b[8..12] != b"WAVE" {
        return Err("not a RIFF/WAVE file".into());
    }
    let mut pos = 12;
    let (mut fmt, mut channels, mut sr, mut bits) = (0u16, 0u16, 0u32, 0u16);
    let mut data: Option<&[u8]> = None;
    while pos + 8 <= b.len() {
        let id = &b[pos..pos + 4];
        let size = rd_u32(b, pos + 4) as usize;
        let body = pos + 8;
        if body + size > b.len() {
            break;
        }
        match id {
            b"fmt " => {
                fmt = rd_u16(b, body);
                channels = rd_u16(b, body + 2);
                sr = rd_u32(b, body + 4);
                bits = rd_u16(b, body + 14);
            }
            b"data" => data = Some(&b[body..body + size]),
            _ => {}
        }
        pos = body + size + (size & 1); // chunks are word-aligned
    }
    let data = data.ok_or("no data chunk")?;
    if channels == 0 {
        return Err("zero channels".into());
    }
    let frame = (bits / 8) as usize * channels as usize;
    let frames = data.len() / frame.max(1);
    let mut left = Vec::with_capacity(frames);
    let mut right = Vec::with_capacity(frames);
    for f in 0..frames {
        let base = f * frame;
        let sample = |ch: usize| -> f32 {
            let o = base + ch * (bits / 8) as usize;
            match (fmt, bits) {
                (1, 16) => rd_u16(data, o) as i16 as f32 / 32768.0,
                (3, 32) => f32::from_le_bytes([data[o], data[o + 1], data[o + 2], data[o + 3]]),
                _ => 0.0,
            }
        };
        left.push(sample(0));
        right.push(if channels > 1 { sample(1) } else { sample(0) });
    }
    if fmt != 1 && fmt != 3 {
        return Err(format!("unsupported WAV format tag {fmt}"));
    }
    Ok(Pcm { left, right, sample_rate: sr })
}

/// Write mono float PCM as a 16-bit WAV.
pub fn write_wav_mono(path: &Path, samples: &[f32], sample_rate: u32) -> Result<(), String> {
    let mut out = Vec::with_capacity(44 + samples.len() * 2);
    let data_len = (samples.len() * 2) as u32;
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data_len).to_le_bytes());
    out.extend_from_slice(b"WAVE");
    out.extend_from_slice(b"fmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM
    out.extend_from_slice(&1u16.to_le_bytes()); // mono
    out.extend_from_slice(&sample_rate.to_le_bytes());
    out.extend_from_slice(&(sample_rate * 2).to_le_bytes()); // byte rate
    out.extend_from_slice(&2u16.to_le_bytes()); // block align
    out.extend_from_slice(&16u16.to_le_bytes()); // bits
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_len.to_le_bytes());
    for &s in samples {
        let v = (s.clamp(-1.0, 1.0) * 32767.0) as i16;
        out.extend_from_slice(&v.to_le_bytes());
    }
    std::fs::File::create(path)
        .map_err(|e| e.to_string())?
        .write_all(&out)
        .map_err(|e| e.to_string())
}

/// Player state shared with the Slint UI.
pub struct Player {
    pub split: Option<StemSplit>,
    pub volumes: [f32; 4],
    pub muted: [bool; 4],
    pub soloed: [bool; 4],
}

impl Default for Player {
    fn default() -> Self {
        Player { split: None, volumes: [0.8; 4], muted: [false; 4], soloed: [false; 4] }
    }
}

impl Player {
    /// Decode + separate a WAV file into four stems via the shared core.
    pub fn load_wav(&mut self, path: &Path) -> Result<(), String> {
        let pcm = read_wav(path)?;
        let split = separate(&pcm.left, &pcm.right, pcm.sample_rate.max(1) as usize, &CoherenceSeparator);
        self.split = Some(split);
        Ok(())
    }

    /// Effective gain for a stem given mute/solo (persistent-volume contract).
    pub fn effective_gain(&self, stem: usize) -> f32 {
        let any_solo = self.soloed.iter().any(|&s| s);
        let audible = if any_solo { self.soloed[stem] } else { !self.muted[stem] };
        if audible { self.volumes[stem].clamp(0.0, 1.0) } else { 0.0 }
    }

    /// Export the four stems next to `dir` as `<stem>.wav`.
    pub fn export_stems(&self, dir: &Path) -> Result<(), String> {
        let split = self.split.as_ref().ok_or("nothing loaded")?;
        let sr = split.sample_rate as u32;
        for (i, name) in STEMS.iter().enumerate() {
            let samples = match i {
                0 => &split.drums,
                1 => &split.vocals,
                2 => &split.bass,
                _ => &split.melody,
            };
            write_wav_mono(&dir.join(format!("{name}.wav")), samples, sr)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use stemacle_dsp::{FFT_SIZE, HOP_SIZE, SR};

    fn synth(len: usize) -> Vec<f32> {
        (0..len).map(|i| (0.02 * i as f32).sin() * 0.5).collect()
    }

    #[test]
    fn wav_round_trip() {
        let dir = std::env::temp_dir();
        let path = dir.join("stemacle_test.wav");
        let samples = synth(2000);
        write_wav_mono(&path, &samples, 44100).unwrap();
        let pcm = read_wav(&path).unwrap();
        assert_eq!(pcm.sample_rate, 44100);
        assert_eq!(pcm.left.len(), 2000);
        // 16-bit quantization tolerance
        for i in 0..2000 {
            assert!((pcm.left[i] - samples[i]).abs() < 1e-3, "sample {i}");
        }
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn load_and_export_round_trips() {
        let dir = std::env::temp_dir().join("stemacle_export_test");
        let _ = std::fs::create_dir_all(&dir);
        let src = dir.join("in.wav");
        write_wav_mono(&src, &synth(FFT_SIZE + 50 * HOP_SIZE), SR as u32).unwrap();

        let mut p = Player::default();
        p.load_wav(&src).unwrap();
        assert!(p.split.is_some());
        p.export_stems(&dir).unwrap();
        for name in ["drums", "vocals", "bass", "melody"] {
            assert!(dir.join(format!("{name}.wav")).exists(), "{name}.wav missing");
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn solo_overrides_mute_with_persistent_volume() {
        let mut p = Player::default();
        p.volumes = [0.5, 0.6, 0.7, 0.8];
        p.muted = [true, false, false, false];
        // no solo: muted stem 0 silent, others at their volume
        assert_eq!(p.effective_gain(0), 0.0);
        assert_eq!(p.effective_gain(1), 0.6);
        // solo stem 2: only it audible, volumes preserved underneath
        p.soloed[2] = true;
        assert_eq!(p.effective_gain(1), 0.0);
        assert_eq!(p.effective_gain(2), 0.7);
        assert_eq!(p.volumes[1], 0.6, "volume must persist through mute/solo");
    }
}
