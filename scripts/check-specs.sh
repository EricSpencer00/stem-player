#!/usr/bin/env bash
#
# Model-check the TLA+ specs with TLC.
#
#   LoopLinking.cfg        fixed contract  → expect NO error
#   LoopLinking_naive.cfg  naive/buggy     → expect an AllRowConsistent violation
#                                            (the stale-allLoopBars malformed state)
#
# Requires Java and tla2tools.jar. Point TLA2TOOLS at a local jar, or the script
# fetches v1.8.0 into the system temp dir.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPECS="$ROOT/specs"
JAR="${TLA2TOOLS:-${TMPDIR:-/tmp}/tla2tools.jar}"

if [ ! -f "$JAR" ]; then
  echo "==> Fetching tla2tools.jar -> $JAR"
  curl -fsSL -o "$JAR" \
    https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
fi

run() { java -cp "$JAR" tlc2.TLC -config "$2" "$1"; }

echo "==> LoopLinking (fixed): expect NO error"
run "$SPECS/LoopLinking.tla" "$SPECS/LoopLinking.cfg" \
  | grep -E "Model checking completed|Invariant .* violated|distinct states"

echo
echo "==> LoopLinking (naive): expect an AllRowConsistent violation + trace"
if run "$SPECS/LoopLinking.tla" "$SPECS/LoopLinking_naive.cfg" \
     | grep -E "Invariant .* violated|SetAllLoop|SetStemLoop"; then
  echo "    (violation reported as expected)"
fi
