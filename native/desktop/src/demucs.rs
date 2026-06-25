//! High-quality separation by shelling out to the real Demucs (htdemucs) via
//! `models/separate.py`. This is the desktop "hack" that trades self-contained
//! packaging for true htdemucs quality — the native app decodes audio and hands
//! Python a WAV, so there is no ffmpeg/torchcodec dependency in the hot path.
//!
//! Configured by env so a shipped build can point at a bundled runtime:
//!   STEMACLE_DEMUCS_PYTHON  python interpreter (default: repo venv)
//!   STEMACLE_DEMUCS_SCRIPT  separate.py path   (default: repo models/separate.py)
//!   STEMACLE_DEMUCS_MODEL   model name         (default: htdemucs)

use std::path::{Path, PathBuf};
use std::process::Command;

use crate::player::read_wav;

pub struct DemucsConfig {
    pub python: PathBuf,
    pub script: PathBuf,
    pub model: String,
}

impl DemucsConfig {
    /// Resolve config from env, falling back to the in-repo venv + script.
    pub fn from_env() -> Self {
        let repo = repo_root();
        let python = std::env::var_os("STEMACLE_DEMUCS_PYTHON")
            .map(PathBuf::from)
            .unwrap_or_else(|| repo.join("models/.venv-models/bin/python"));
        let script = std::env::var_os("STEMACLE_DEMUCS_SCRIPT")
            .map(PathBuf::from)
            .unwrap_or_else(|| repo.join("models/separate.py"));
        let model = std::env::var("STEMACLE_DEMUCS_MODEL").unwrap_or_else(|_| "htdemucs".into());
        DemucsConfig { python, script, model }
    }

    /// Whether the Demucs runtime is present (else callers use the DSP fallback).
    pub fn available(&self) -> bool {
        self.python.exists() && self.script.exists()
    }
}

fn repo_root() -> PathBuf {
    // native/desktop/<bin> → repo root is three up from CARGO_MANIFEST_DIR.
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..").canonicalize()
        .unwrap_or_else(|_| PathBuf::from("."))
}

/// Run htdemucs on `input_wav`, returning the four mono stems in canonical order
/// (drums, vocals, bass, melody). Stereo model output is down-mixed to mono.
pub fn separate_file(input_wav: &Path, cfg: &DemucsConfig) -> Result<[Vec<f32>; 4], String> {
    let out_dir = std::env::temp_dir().join(format!("stemacle-demucs-{}", std::process::id()));
    std::fs::create_dir_all(&out_dir).map_err(|e| e.to_string())?;

    let status = Command::new(&cfg.python)
        .arg(&cfg.script)
        .arg(input_wav)
        .arg(&out_dir)
        .arg("--model")
        .arg(&cfg.model)
        .status()
        .map_err(|e| format!("failed to launch demucs: {e}"))?;
    if !status.success() {
        return Err(format!("demucs exited with {status}"));
    }

    let read_mono = |name: &str| -> Result<Vec<f32>, String> {
        let pcm = read_wav(&out_dir.join(format!("{name}.wav")))?;
        Ok(pcm
            .left
            .iter()
            .zip(pcm.right.iter())
            .map(|(&l, &r)| (l + r) * 0.5)
            .collect())
    };
    let stems = [
        read_mono("drums")?,
        read_mono("vocals")?,
        read_mono("bass")?,
        read_mono("melody")?,
    ];
    let _ = std::fs::remove_dir_all(&out_dir);
    Ok(stems)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_resolves_and_reports_availability() {
        let cfg = DemucsConfig::from_env();
        // Either the repo venv exists (available) or it doesn't — both are valid;
        // we only assert the script path is resolved to the in-repo separate.py
        // when the env var is unset.
        assert!(cfg.script.ends_with("separate.py"));
        assert_eq!(cfg.model, "htdemucs");
        let _ = cfg.available();
    }
}
