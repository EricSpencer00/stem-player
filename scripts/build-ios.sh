#!/usr/bin/env bash
#
# One-shot, reproducible iOS build.
#
#   1. fetch the bundled Spleeter ONNX models
#   2. build the shared Rust core xcframework
#   3. (re)generate the Xcode project from project.yml
#   4. build StemacleiOS
#
# Step 4 uses *isolated* SwiftPM directories. SwiftPM's shared cache
# (~/Library/Caches/org.swift.swiftpm) intermittently fails the ONNX Runtime
# binary-target download with "already exists in file system"; a dedicated
# clone/cache dir sidesteps that bug and is reused across builds so ORT is only
# downloaded once.
#
# Usage:  scripts/build-ios.sh ["<xcodebuild destination>"]
#   default destination: generic/platform=iOS Simulator
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLE="$ROOT/native/apple"
DEST="${1:-generic/platform=iOS Simulator}"
SPM_CLONE="${SPM_CLONE:-$APPLE/.spm-clone}"
SPM_CACHE="${SPM_CACHE:-$APPLE/.spm-cache}"

echo "==> [1/4] Fetching Spleeter models"
bash "$ROOT/scripts/fetch-ios-models.sh"

echo "==> [2/4] Building Rust core xcframework"
bash "$ROOT/scripts/build-apple-xcframework.sh"

echo "==> [3/4] Generating Xcode project"
( cd "$APPLE" && xcodegen generate )

echo "==> [4/4] Building StemacleiOS ($DEST)"
( cd "$APPLE" && xcodebuild build \
    -project Stemacle.xcodeproj -scheme StemacleiOS \
    -sdk iphonesimulator -destination "$DEST" \
    -clonedSourcePackagesDirPath "$SPM_CLONE" \
    -packageCachePath "$SPM_CACHE" \
    CODE_SIGNING_ALLOWED=NO )

echo "==> Done. (SwiftPM dirs: $SPM_CLONE, $SPM_CACHE)"
