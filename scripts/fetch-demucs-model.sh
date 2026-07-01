#!/usr/bin/env bash
#
# Fetch the HT-Demucs single 4-stem ONNX model (~166 MB fp16) the iOS app can use
# for state-of-the-art on-device separation. OPTIONAL and separate from
# fetch-ios-models.sh: if this model is present in Resources/models the app
# prefers it (Demucs > Spleeter > DSP); otherwise it falls back to Spleeter.
#
# Note: Demucs is a large hybrid transformer — bundling adds ~166 MB to the app
# and it needs the CoreML execution provider (ANE) for acceptable speed on a
# real device. Ship this OR the Spleeter models, not both (Demucs supersedes
# Spleeter, which would then be dead weight).
#
# Source: https://huggingface.co/StemSplitio/htdemucs-onnx
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/native/apple/Stemacle/Resources/models"
URL="https://huggingface.co/StemSplitio/htdemucs-onnx/resolve/main/htdemucs_fp16weights.onnx"

mkdir -p "$DEST"
out="$DEST/htdemucs_fp16weights.onnx"
if [[ -f "$out" ]]; then
  echo "==> htdemucs_fp16weights.onnx already present ($(du -h "$out" | cut -f1)) — skipping"
else
  echo "==> Downloading htdemucs_fp16weights.onnx (~166 MB)"
  curl -fL --retry 3 -o "$out" "$URL"
fi
echo "==> Demucs model ready: $out"
ls -lh "$out"
