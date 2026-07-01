#!/usr/bin/env bash
#
# Fetch the Spleeter 2-stem ONNX models the iOS app bundles for neural
# separation (quality parity with the web gold master, which runs the same
# models via onnxruntime-web). These are large (~39 MB each) build assets, so
# they are NOT committed — run this before building the iOS target, the same way
# scripts/build-apple-xcframework.sh produces StemacleCore.xcframework.
#
# Source: https://huggingface.co/csukuangfj/sherpa-onnx-spleeter-2stems
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/native/apple/Stemacle/Resources/models"
BASE="https://huggingface.co/csukuangfj/sherpa-onnx-spleeter-2stems/resolve/main"

mkdir -p "$DEST"
for model in vocals accompaniment; do
  out="$DEST/$model.onnx"
  if [[ -f "$out" ]]; then
    echo "==> $model.onnx already present ($(du -h "$out" | cut -f1)) — skipping"
    continue
  fi
  echo "==> Downloading $model.onnx"
  curl -fL --retry 3 -o "$out" "$BASE/$model.onnx"
done
echo "==> Models ready in $DEST"
ls -lh "$DEST"
