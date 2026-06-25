---- MODULE Navigation ----
EXTENDS Naturals, FiniteSets, TLC

\* Screen-navigation and project-lifecycle model for the native Stemacle apps
\* (iOS + desktop). Captures the "think bigger" architecture: a tabbed shell
\* where the user can always import / change song without exiting, and where
\* separation jobs run in the background while the user navigates.
\*
\* This is a behavioral contract for the SwiftUI/Slint navigation, not the audio
\* DSP (that lives in LoopTiming.tla and the Rust core).

CONSTANTS
  Songs        \* finite set of importable song ids, e.g. {s1, s2, s3}

Tabs == {"Library", "Splitter", "Mixer", "Settings"}
None == "None"

\* Job lifecycle for a song's separation.
States == {"absent", "pending", "processing", "done", "error"}

VARIABLES
  tab,        \* current tab
  importing,  \* is the import sheet open
  job,        \* [Songs -> States]  background split queue
  active,     \* Songs \cup {None}   project loaded in the Splitter
  playing     \* BOOLEAN             transport state

vars == << tab, importing, job, active, playing >>

\* Done songs form the Library; mixer needs at least two done songs.
Library == { s \in Songs : job[s] = "done" }

TypeOK ==
  /\ tab \in Tabs
  /\ importing \in BOOLEAN
  /\ job \in [Songs -> States]
  /\ active \in (Songs \cup {None})
  /\ playing \in BOOLEAN

Init ==
  /\ tab = "Library"
  /\ importing = FALSE
  /\ job = [s \in Songs |-> "absent"]
  /\ active = None
  /\ playing = FALSE

\* --- Navigation: every tab is always reachable (no dead ends) ---
SwitchTab(t) ==
  /\ t \in Tabs
  /\ tab' = t
  /\ UNCHANGED << importing, job, active, playing >>

\* --- Import / change song: reachable from ANY tab, even mid-playback ---
OpenImport ==
  /\ ~importing
  /\ importing' = TRUE
  /\ UNCHANGED << tab, job, active, playing >>

CancelImport ==
  /\ importing
  /\ importing' = FALSE
  /\ UNCHANGED << tab, job, active, playing >>

\* Enqueue a split job and close the sheet. The user keeps navigating.
StartSplit(s) ==
  /\ importing
  /\ job[s] \in {"absent", "error"}
  /\ job' = [job EXCEPT ![s] = "pending"]
  /\ importing' = FALSE
  /\ UNCHANGED << tab, active, playing >>

\* --- Background queue: advances regardless of which tab is showing ---
AdvanceJob(s) ==
  /\ job[s] = "pending"
  /\ job' = [job EXCEPT ![s] = "processing"]
  /\ UNCHANGED << tab, importing, active, playing >>

FinishJob(s) ==
  /\ job[s] = "processing"
  /\ job' = [job EXCEPT ![s] = "done"]
  /\ UNCHANGED << tab, importing, active, playing >>

\* --- Open a finished project in the Splitter (no re-split needed) ---
OpenProject(s) ==
  /\ job[s] = "done"
  /\ active' = s
  /\ tab' = "Splitter"
  /\ UNCHANGED << importing, job, playing >>

\* --- Transport ---
Play ==
  /\ active # None
  /\ ~playing
  /\ playing' = TRUE
  /\ UNCHANGED << tab, importing, job, active >>

Pause ==
  /\ playing
  /\ playing' = FALSE
  /\ UNCHANGED << tab, importing, job, active >>

\* Switching the loaded song stops playback but keeps you in the app.
ChangeSong(s) ==
  /\ job[s] = "done"
  /\ s # active
  /\ active' = s
  /\ playing' = FALSE
  /\ tab' = "Splitter"
  /\ UNCHANGED << importing, job >>

Next ==
  \/ \E t \in Tabs : SwitchTab(t)
  \/ OpenImport
  \/ CancelImport
  \/ \E s \in Songs : StartSplit(s)
  \/ \E s \in Songs : AdvanceJob(s)
  \/ \E s \in Songs : FinishJob(s)
  \/ \E s \in Songs : OpenProject(s)
  \/ \E s \in Songs : ChangeSong(s)
  \/ Play
  \/ Pause

\* Fairness: queued jobs make progress; the user can always navigate.
Fairness ==
  /\ \A s \in Songs : WF_vars(AdvanceJob(s))
  /\ \A s \in Songs : WF_vars(FinishJob(s))

Spec == Init /\ [][Next]_vars /\ Fairness

\* ---------------- Safety invariants ----------------

\* You can only play a project that has actually been separated.
PlayingImpliesActive == playing => active # None
ActiveIsDone == active # None => job[active] = "done"

\* No dead ends: from every reachable state, every tab is one step away, and
\* import (change song) is available whenever the sheet is closed.
CanAlwaysSwitchTab == \A t \in Tabs : ENABLED SwitchTab(t)
CanAlwaysChangeSong == ~importing => ENABLED OpenImport

Safety ==
  /\ TypeOK
  /\ PlayingImpliesActive
  /\ ActiveIsDone
  /\ CanAlwaysSwitchTab
  /\ CanAlwaysChangeSong

\* ---------------- Liveness ----------------

\* Every queued split eventually finishes (background processing completes).
JobsComplete == \A s \in Songs : (job[s] = "pending") ~> (job[s] = "done")

\* The user is never trapped: from anywhere they can get back to the Library.
CanReachLibrary == []<>(ENABLED SwitchTab("Library"))

Liveness ==
  /\ JobsComplete
  /\ CanReachLibrary
====
