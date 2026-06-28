# Stemacle Native Navigation Architecture

The current apps have one screen (the player) and no way to change song without
relaunching. This is the bigger structure: a tabbed shell where you can always
import or switch songs, and where separation runs in the background while you
keep using the app. It is formally specified and model-checked in
[`specs/Navigation.tla`](../specs/Navigation.tla) (TLC: 1,280 states, all
invariants hold).

## Screens (tabs)

| Tab | Role |
|---|---|
| **Library** | Home. Every split song as a card (art, title, BPM, key). Tap to open in the Splitter. An **Import** action is always here. |
| **Splitter** | The player (today's main screen): disc, spectrogram lanes, stems, loops, transport. Loads a project instantly from the Library (no re-split). |
| **Mixer** | Two-deck stem mashup (future): load two projects, match tempo/key, interchange stems. |
| **Settings** | Separation server, cache, about, privacy/terms links. |

A persistent **Import** affordance lives in the top bar of every tab, so "change
song" never means "exit the app."

## Lifecycle of a song

```
Import ──StartSplit──▶ pending ──▶ processing ──▶ done ──▶ Library card
                         (background queue; advances on any tab)         │
                                                                          ▼
                                                              OpenProject → Splitter
```

Key behaviors the model guarantees:

- **No dead ends** (`CanAlwaysSwitchTab`): every tab is one tap away from any state.
- **Always change song** (`CanAlwaysChangeSong`): Import is enabled from anywhere
  the sheet is closed, including mid-playback.
- **Background splitting** (`AdvanceJob`/`FinishJob` are enabled regardless of the
  current tab): a job started from Import keeps progressing while you browse the
  Library or tweak Settings; the progress ring we already built surfaces it.
- **Jobs complete** (`JobsComplete`, under fairness): every queued split
  eventually reaches `done`.
- **Play only what's split** (`PlayingImpliesActive` + `ActiveIsDone`): the
  transport is live only when a finished project is loaded.

## Why this matters for the current bugs

- *"No way to change song without exiting"* → the **Library tab + persistent
  Import** are the fix; `ChangeSong` swaps the loaded project without leaving.
- *"Stuck on the 15s demo"* → once Import is always available, the demo is just
  one of many Library entries, not the only reachable audio.
- Splitting a new song no longer blocks the UI: it enqueues and runs in the
  background while the user stays in the Library or plays an existing project.

## Mapping to code

- iOS/macOS: a `TabView` root (`Library | Splitter | Mixer | Settings`), the
  existing player becomes the Splitter tab, a shared `LibraryStore` +
  `SplitQueue` observable drives both. Import is a toolbar button on every tab.
- Slint: the same shell as a sidebar; the queue is the Rust worker pool we
  already have (`load_stems` on a thread), surfaced as a list.

This doc + the TLA spec are the contract; the SwiftUI/Slint wiring implements it.
