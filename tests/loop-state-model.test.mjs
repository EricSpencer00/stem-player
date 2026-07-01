// Explicit-state model checker for the Stemacle loop state machine.
//
// The app tracks a loop length per stem (`loopBars[stem]`) AND an "All" row
// linked-loop length (`allLoopBars`). The invariant the UI relies on is:
//
//   When the All row shows a length as active, every stem is actually looping
//   at that same length, over the same window.
//
// This BFS enumerates every reachable state under two transition relations:
//   - "naive": individual per-stem loop edits leave `all` untouched (the bug the
//     web gold master avoids and the native app used to have).
//   - "fixed": any individual per-stem edit clears the All indicator, mirroring
//     the web `setStemLoop` → `clearAllLoopIndicator()` contract.
//
// It confirms the invariant is *violable* under "naive" (with a counterexample
// trace) and *holds on every reachable state* under "fixed" — the guarantee the
// SwiftUI `StemPlayerViewModel` must implement.

import assert from 'node:assert/strict';
import test from 'node:test';

const STEMS = 4;
const LENGTHS = [1, 2]; // abstract bar lengths (0 = no loop)
const POSITIONS = [0, 1]; // abstract transport positions (drive a loop's window origin)

const initial = () => ({
  loop: Array(STEMS).fill(0), // per-stem loop length, 0 = none
  origin: Array(STEMS).fill(-1), // window origin id while looping, -1 = none
  all: 0, // All-row selected length (mirrors allLoopBars), 0 = none
  pos: 0, // current transport position
});

const key = (s) => `${s.loop.join('')}|${s.origin.join('')}|a${s.all}|p${s.pos}`;
const clone = (s) => ({ loop: [...s.loop], origin: [...s.origin], all: s.all, pos: s.pos });

// Every enabled transition from `s`, as { label, next } pairs. `clearAll`
// controls whether individual per-stem edits also clear the All indicator.
function successors(s, { clearAll }) {
  const out = [];
  // Seek to a different transport position (changes future loop origins).
  for (const p of POSITIONS) {
    if (p === s.pos) continue;
    const n = clone(s);
    n.pos = p;
    out.push({ label: `seek(${p})`, next: n });
  }
  // Per-stem loop set.
  for (let stem = 0; stem < STEMS; stem++) {
    for (const len of LENGTHS) {
      const n = clone(s);
      n.loop[stem] = len;
      n.origin[stem] = s.pos;
      if (clearAll) n.all = 0;
      out.push({ label: `setStemLoop(${stem},${len})`, next: n });
    }
    // Per-stem loop clear.
    if (s.loop[stem] !== 0) {
      const n = clone(s);
      n.loop[stem] = 0;
      n.origin[stem] = -1;
      if (clearAll) n.all = 0;
      out.push({ label: `clearStemLoop(${stem})`, next: n });
    }
  }
  // All-row linked loop set: one window applied to every stem.
  for (const len of LENGTHS) {
    const n = clone(s);
    n.all = len;
    for (let stem = 0; stem < STEMS; stem++) {
      n.loop[stem] = len;
      n.origin[stem] = s.pos;
    }
    out.push({ label: `setAllLoop(${len})`, next: n });
  }
  // All-row clear.
  {
    const n = clone(s);
    n.all = 0;
    n.loop = Array(STEMS).fill(0);
    n.origin = Array(STEMS).fill(-1);
    out.push({ label: 'clearAllLoop', next: n });
  }
  return out;
}

// Invariants every reachable state must satisfy.
const INVARIANTS = [
  {
    name: 'AllRowLengthConsistent',
    holds: (s) => s.all === 0 || s.loop.every((l) => l === s.all),
  },
  {
    name: 'AllRowSharedWindow',
    // When linked, every stem shares one window origin (set together).
    holds: (s) =>
      s.all === 0 || s.origin.every((o) => o !== -1 && o === s.origin[0]),
  },
  {
    name: 'LoopWellFormed',
    // A stem has a window origin iff it is looping.
    holds: (s) => s.loop.every((l, i) => (l !== 0) === (s.origin[i] !== -1)),
  },
];

// BFS the full reachable state space; return reachable count and the first
// invariant violation found (with a shortest action trace from the initial state).
function explore({ clearAll }) {
  const start = initial();
  const startKey = key(start);
  const seen = new Map([[startKey, start]]);
  const parent = new Map([[startKey, null]]);
  const queue = [start];
  let firstViolation = null;

  const checkState = (s) => {
    for (const inv of INVARIANTS) {
      if (!inv.holds(s) && !firstViolation) {
        firstViolation = { invariant: inv.name, state: s, trace: traceTo(key(s)) };
      }
    }
  };
  const traceTo = (k) => {
    const steps = [];
    let cur = k;
    while (parent.get(cur)) {
      const { label, from } = parent.get(cur);
      steps.push(label);
      cur = from;
    }
    return steps.reverse();
  };

  checkState(start);
  while (queue.length) {
    const s = queue.shift();
    for (const { label, next } of successors(s, { clearAll })) {
      const k = key(next);
      if (seen.has(k)) continue;
      seen.set(k, next);
      parent.set(k, { label, from: key(s) });
      checkState(next);
      queue.push(next);
    }
  }
  return { reachable: seen.size, firstViolation };
}

test('model checker: the invariant is real — the naive model reaches a malformed All-row state', () => {
  const { firstViolation } = explore({ clearAll: false });
  assert.ok(
    firstViolation,
    'expected the naive (no clear-all-indicator) model to violate an All-row invariant',
  );
  // The reported bug: an All loop followed by an individual stem edit.
  assert.ok(
    firstViolation.trace.some((l) => l.startsWith('setAllLoop')),
    `trace should start from an All loop: ${firstViolation.trace.join(' → ')}`,
  );
  // Surface the counterexample so the guard documents the exact failure mode.
  console.log(
    `  naive-model counterexample [${firstViolation.invariant}]: ${firstViolation.trace.join(' → ')}`,
  );
});

test('model checker: the fixed model has NO malformed loop state across all reachable states', () => {
  const { reachable, firstViolation } = explore({ clearAll: true });
  assert.equal(
    firstViolation,
    null,
    firstViolation &&
      `malformed state reachable: [${firstViolation.invariant}] via ${firstViolation.trace.join(' → ')}`,
  );
  assert.ok(reachable > 50, `expected a non-trivial reachable state space, got ${reachable}`);
});
