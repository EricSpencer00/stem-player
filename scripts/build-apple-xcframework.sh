#!/usr/bin/env bash
#
# Build StemacleCore.xcframework from the shared Rust core (stemacle-ffi).
#
# Produces static-library slices for:
#   - macOS            (arm64)
#   - iOS device       (arm64)
#   - iOS simulator    (arm64 + x86_64, lipo'd)
# bundled with the C header + module map so Swift can `import StemacleCore`.
#
# This is the canonical, best-practice way to ship a Rust core to Apple: one
# binary artifact Xcode/SPM links directly, no per-app build scripting.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/native/core"
FFI="$CORE/stemacle-ffi"
OUT="$ROOT/native/apple"
BUILD="$OUT/build"
XCF="$OUT/StemacleCore.xcframework"
LIB="libstemacle_ffi.a"
HEADERS="$BUILD/headers"

echo "==> Building stemacle-ffi static libs (release)"
rm -rf "$BUILD" "$XCF"
mkdir -p "$BUILD" "$HEADERS"

build_target() {
  local target="$1"
  echo "    cargo build --release --target $target"
  ( cd "$CORE" && cargo build --release -p stemacle-ffi --target "$target" )
}

build_target aarch64-apple-darwin
build_target aarch64-apple-ios
build_target aarch64-apple-ios-sim
build_target x86_64-apple-ios

# Fat simulator slice (arm64 + x86_64).
mkdir -p "$BUILD/ios-sim"
lipo -create \
  "$CORE/target/aarch64-apple-ios-sim/release/$LIB" \
  "$CORE/target/x86_64-apple-ios/release/$LIB" \
  -output "$BUILD/ios-sim/$LIB"

# Headers + module map shared by every slice.
cp "$FFI/include/stemacle.h" "$HEADERS/"
cp "$FFI/include/module.modulemap" "$HEADERS/"

echo "==> Creating XCFramework"
xcodebuild -create-xcframework \
  -library "$CORE/target/aarch64-apple-darwin/release/$LIB" -headers "$HEADERS" \
  -library "$CORE/target/aarch64-apple-ios/release/$LIB" -headers "$HEADERS" \
  -library "$BUILD/ios-sim/$LIB" -headers "$HEADERS" \
  -output "$XCF"

echo "==> Done: $XCF"
ls "$XCF"
