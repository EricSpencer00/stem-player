//! Stemacle desktop shell (Windows/Linux) — Slint UI over the shared Rust core.
//!
//! The heavy lifting (decode, separation, mixing, export) lives in `player.rs`,
//! which is unit-tested with `cargo test`. This file only wires the UI events.

mod demucs;
mod playback;
mod player;

use std::cell::RefCell;
use std::rc::Rc;
use std::sync::mpsc::{channel, Receiver};

use playback::AudioOutput;
use player::{load_stems, LoadedStems, Player};
use slint::{Model, Timer, TimerMode};

slint::include_modules!();

type LoadResult = Result<LoadedStems, String>;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let window = MainWindow::new()?;
    let state = Rc::new(RefCell::new(Player::default()));
    // Audio is optional: if no output device is available the app still loads,
    // separates, and exports — playback just stays inert.
    let audio: Rc<Option<AudioOutput>> = Rc::new(AudioOutput::new().ok());

    // Worker-thread separation results are polled on the UI thread by a timer,
    // because the player state / cpal stream are not Send.
    let (tx, rx) = channel::<LoadResult>();
    let rx: Rc<RefCell<Receiver<LoadResult>>> = Rc::new(RefCell::new(rx));
    let poll_timer = Timer::default();
    {
        let weak = window.as_weak();
        let state = state.clone();
        let audio = audio.clone();
        let rx = rx.clone();
        poll_timer.start(TimerMode::Repeated, std::time::Duration::from_millis(150), move || {
            let Ok(result) = rx.borrow().try_recv() else { return };
            let Some(win) = weak.upgrade() else { return };
            match result {
                Ok(loaded) => {
                    let hq = loaded.high_quality;
                    let bpm = loaded.tempo.bpm;
                    {
                        let mut p = state.borrow_mut();
                        p.set_loaded(loaded);
                        if let (Some(out), Some(stems)) = (audio.as_ref(), p.stem_buffers()) {
                            out.load(stems);
                            out.set_gains(p.effective_gains());
                        }
                    }
                    win.set_ready(true);
                    win.set_playing(false);
                    let label = if hq { "htdemucs" } else { "DSP" };
                    win.set_status(format!("Ready · {} BPM · {label}", bpm as i32).into());
                }
                Err(e) => win.set_status(format!("Load failed: {e}").into()),
            }
        });
    }

    // Open + separate a WAV on a worker thread (htdemucs can take minutes).
    {
        let weak = window.as_weak();
        let tx = tx.clone();
        window.on_load_clicked(move || {
            let Some(win) = weak.upgrade() else { return };
            if let Some(path) = rfd::FileDialog::new()
                .add_filter("Audio (WAV)", &["wav"])
                .pick_file()
            {
                win.set_ready(false);
                win.set_status("Separating (high quality)… this can take a minute".into());
                let tx = tx.clone();
                std::thread::spawn(move || {
                    let _ = tx.send(load_stems(&path));
                });
            }
        });
    }

    // Transport.
    {
        let weak = window.as_weak();
        let audio = audio.clone();
        window.on_play_clicked(move || {
            let Some(win) = weak.upgrade() else { return };
            if let Some(out) = audio.as_ref() {
                out.toggle_play();
                win.set_playing(out.is_playing());
            }
        });
    }
    {
        let weak = window.as_weak();
        let audio = audio.clone();
        window.on_stop_clicked(move || {
            let Some(win) = weak.upgrade() else { return };
            if let Some(out) = audio.as_ref() {
                out.stop();
            }
            win.set_playing(false);
        });
    }

    // Export stems to a chosen folder.
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_export_clicked(move || {
            let Some(win) = weak.upgrade() else { return };
            if let Some(dir) = rfd::FileDialog::new().pick_folder() {
                match state.borrow().export_stems(&dir) {
                    Ok(()) => win.set_status("Exported four stems".into()),
                    Err(e) => win.set_status(format!("Export failed: {e}").into()),
                }
            }
        });
    }

    // Per-stem mixing.
    {
        let weak = window.as_weak();
        let state = state.clone();
        let audio = audio.clone();
        window.on_volume_changed(move |i, v| {
            state.borrow_mut().volumes[i as usize] = v;
            push_mix(&weak, &state, &audio);
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        let audio = audio.clone();
        window.on_mute_toggled(move |i| {
            let m = &mut state.borrow_mut().muted[i as usize];
            *m = !*m;
            push_mix(&weak, &state, &audio);
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        let audio = audio.clone();
        window.on_solo_toggled(move |i| {
            let s = &mut state.borrow_mut().soloed[i as usize];
            *s = !*s;
            push_mix(&weak, &state, &audio);
        });
    }

    window.run()?;
    Ok(())
}

/// Apply a mixing change: update the audio gains and refresh the UI rows.
fn push_mix(
    weak: &slint::Weak<MainWindow>,
    state: &Rc<RefCell<Player>>,
    audio: &Rc<Option<AudioOutput>>,
) {
    if let Some(out) = audio.as_ref() {
        out.set_gains(state.borrow().effective_gains());
    }
    sync_rows(weak, state);
}

/// Push the player's mixing state back into the UI rows.
fn sync_rows(weak: &slint::Weak<MainWindow>, state: &Rc<RefCell<Player>>) {
    let Some(win) = weak.upgrade() else { return };
    let p = state.borrow();
    let rows = win.get_stems();
    for i in 0..rows.row_count() {
        if let Some(mut row) = rows.row_data(i) {
            row.volume = p.volumes[i];
            row.muted = p.muted[i];
            row.soloed = p.soloed[i];
            rows.set_row_data(i, row);
        }
    }
}
