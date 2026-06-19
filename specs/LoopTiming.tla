---- MODULE LoopTiming ----
EXTENDS Naturals, TLC

\* Discrete timing model for index.html loop quantization.
\* One tick is an abstract audio time quantum, not a wall-clock millisecond.

CONSTANTS
  Stems,
  DurationTicks,
  BeatTicks,
  BeatsPerMeasure,
  MeasureOffset,
  LoopLengths

ASSUME DurationTicks > 0
ASSUME BeatTicks > 0
ASSUME BeatsPerMeasure = 4
ASSUME MeasureOffset \in 0..((BeatTicks * BeatsPerMeasure) - 1)
ASSUME LoopLengths \subseteq 1..DurationTicks

MeasureTicks == BeatTicks * BeatsPerMeasure

\* Short loops quantize to their own subdivision. One- and two-measure loops
\* quantize to bar starts.
Grid(len) == IF len < MeasureTicks THEN len ELSE MeasureTicks

Aligned(t, grid) == \E n \in Nat : t = MeasureOffset + (n * grid)

NextBoundary(t, len) ==
  CHOOSE boundary \in 0..DurationTicks :
    /\ boundary >= t
    /\ Aligned(boundary, Grid(len))
    /\ \A other \in 0..DurationTicks :
      (other >= t /\ Aligned(other, Grid(len))) => boundary <= other

VARIABLES
  transport,
  loopOn,
  loopStart,
  loopEnd,
  selectedLength

vars == << transport, loopOn, loopStart, loopEnd, selectedLength >>

Init ==
  /\ transport = 0
  /\ loopOn = [stem \in Stems |-> FALSE]
  /\ loopStart = [stem \in Stems |-> 0]
  /\ loopEnd = [stem \in Stems |-> 0]
  /\ selectedLength = [stem \in Stems |-> 0]

Tick ==
  /\ transport < DurationTicks
  /\ transport' = transport + 1
  /\ UNCHANGED << loopOn, loopStart, loopEnd, selectedLength >>

EnableLoop(stem, len) ==
  LET start == NextBoundary(transport, len) IN
  /\ len \in LoopLengths
  /\ start + len <= DurationTicks
  /\ loopOn' = [loopOn EXCEPT ![stem] = TRUE]
  /\ loopStart' = [loopStart EXCEPT ![stem] = start]
  /\ loopEnd' = [loopEnd EXCEPT ![stem] = start + len]
  /\ selectedLength' = [selectedLength EXCEPT ![stem] = len]
  /\ UNCHANGED transport

RejectTooLong(stem, len) ==
  LET start == NextBoundary(transport, len) IN
  /\ len \in LoopLengths
  /\ start + len > DurationTicks
  /\ loopOn' = [loopOn EXCEPT ![stem] = FALSE]
  /\ loopStart' = [loopStart EXCEPT ![stem] = 0]
  /\ loopEnd' = [loopEnd EXCEPT ![stem] = 0]
  /\ selectedLength' = [selectedLength EXCEPT ![stem] = 0]
  /\ UNCHANGED transport

DisableLoop(stem) ==
  /\ loopOn' = [loopOn EXCEPT ![stem] = FALSE]
  /\ loopStart' = [loopStart EXCEPT ![stem] = 0]
  /\ loopEnd' = [loopEnd EXCEPT ![stem] = 0]
  /\ selectedLength' = [selectedLength EXCEPT ![stem] = 0]
  /\ UNCHANGED transport

Next ==
  \/ Tick
  \/ \E stem \in Stems, len \in LoopLengths : EnableLoop(stem, len)
  \/ \E stem \in Stems, len \in LoopLengths : RejectTooLong(stem, len)
  \/ \E stem \in Stems : DisableLoop(stem)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ transport \in 0..DurationTicks
  /\ loopOn \in [Stems -> BOOLEAN]
  /\ loopStart \in [Stems -> 0..DurationTicks]
  /\ loopEnd \in [Stems -> 0..DurationTicks]
  /\ selectedLength \in [Stems -> (LoopLengths \cup {0})]

ActiveLoopShape ==
  \A stem \in Stems :
    loopOn[stem] =>
      /\ selectedLength[stem] \in LoopLengths
      /\ loopEnd[stem] = loopStart[stem] + selectedLength[stem]

ActiveLoopAligned ==
  \A stem \in Stems :
    loopOn[stem] => Aligned(loopStart[stem], Grid(selectedLength[stem]))

ActiveLoopInBounds ==
  \A stem \in Stems :
    loopOn[stem] => loopEnd[stem] <= DurationTicks

====
