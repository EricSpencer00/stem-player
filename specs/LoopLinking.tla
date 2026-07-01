---- MODULE LoopLinking ----
EXTENDS Naturals

\* State model for the Stemacle "All row" linked loop vs. per-stem loops.
\*
\* The player keeps a loop length per stem (loopLen) plus an "All row" selected
\* length (allSel, = allLoopBars in StemPlayerViewModel). The UI invariant is:
\* when the All row shows a length, EVERY stem loops at exactly that length.
\*
\* The web gold master maintains this by clearing the All indicator on any
\* individual per-stem edit (setStemLoop -> clearAllLoopIndicator). Toggle
\* ClearAllOnStemEdit to model-check both behaviors: FALSE (the native bug that
\* left allLoopBars stale) reaches a state violating AllRowConsistent; TRUE (the
\* fix) holds the invariant across every reachable state.

CONSTANTS
  Stems,
  Lengths,             \* nonzero loop lengths, e.g. {1, 2}
  ClearAllOnStemEdit   \* TRUE = fixed contract, FALSE = naive (buggy)

None == 0
LenDom == Lengths \cup {None}

ASSUME None \notin Lengths

VARIABLES
  loopLen,   \* [Stems -> LenDom]
  allSel     \* LenDom

vars == << loopLen, allSel >>

Init ==
  /\ loopLen = [s \in Stems |-> None]
  /\ allSel = None

\* Edit one stem's loop; an individual edit clears the All indicator iff fixed.
SetStemLoop(s, len) ==
  /\ loopLen' = [loopLen EXCEPT ![s] = len]
  /\ allSel' = IF ClearAllOnStemEdit THEN None ELSE allSel

ClearStemLoop(s) ==
  /\ loopLen' = [loopLen EXCEPT ![s] = None]
  /\ allSel' = IF ClearAllOnStemEdit THEN None ELSE allSel

\* Link every stem to one length and light the All row.
SetAllLoop(len) ==
  /\ loopLen' = [s \in Stems |-> len]
  /\ allSel' = len

ClearAllLoop ==
  /\ loopLen' = [s \in Stems |-> None]
  /\ allSel' = None

Next ==
  \/ \E s \in Stems, len \in Lengths : SetStemLoop(s, len)
  \/ \E s \in Stems : ClearStemLoop(s)
  \/ \E len \in Lengths : SetAllLoop(len)
  \/ ClearAllLoop

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ loopLen \in [Stems -> LenDom]
  /\ allSel \in LenDom

\* The All row only claims a linked length when every stem loops at that length.
AllRowConsistent ==
  allSel # None => \A s \in Stems : loopLen[s] = allSel

====
