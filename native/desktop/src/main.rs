//! Stemacle desktop shell (Windows/Linux) — Slint UI over the shared Rust core.
//!
//! The heavy lifting (decode, separation, mixing, export) lives in `player.rs`,
//! which is unit-tested with `cargo test`. This file only wires the UI events.

mod player;

use std::cell::RefCell;
use std::rc::Rc;

use player::Player;
use slint::Model;

slint::include_modules!();

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let window = MainWindow::new()?;
    let state = Rc::new(RefCell::new(Player::default()));

    // Open + separate a WAV.
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_load_clicked(move || {
            let Some(win) = weak.upgrade() else { return };
            if let Some(path) = rfd::FileDialog::new()
                .add_filter("Audio (WAV)", &["wav"])
                .pick_file()
            {
                win.set_status("Separating…".into());
                match state.borrow_mut().load_wav(&path) {
                    Ok(()) => {
                        let bpm = state.borrow().split.as_ref().map(|s| s.tempo.bpm).unwrap_or(120.0);
                        win.set_ready(true);
                        win.set_status(format!("Ready · {} BPM", bpm as i32).into());
                    }
                    Err(e) => win.set_status(format!("Load failed: {e}").into()),
                }
            }
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
        window.on_volume_changed(move |i, v| {
            state.borrow_mut().volumes[i as usize] = v;
            sync_rows(&weak, &state);
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_mute_toggled(move |i| {
            let m = &mut state.borrow_mut().muted[i as usize];
            *m = !*m;
            sync_rows(&weak, &state);
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_solo_toggled(move |i| {
            let s = &mut state.borrow_mut().soloed[i as usize];
            *s = !*s;
            sync_rows(&weak, &state);
        });
    }

    window.run()?;
    Ok(())
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
