#!/usr/bin/env bash
#
# Generate the Stemacle AppIcon.appiconset for the native Apple apps from the
# brand release icon, using sips. Produces the iOS single-size 1024 marketing
# icon plus the full macOS size ladder, with a valid Contents.json.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$ROOT/assets/release-icons/stemacle-release-icon-01.png}"
SET="$ROOT/native/apple/Stemacle/Resources/Assets.xcassets/AppIcon.appiconset"

mkdir -p "$SET"
echo "==> Source icon: $SRC"

gen() { # size filename
  sips -s format png -z "$1" "$1" "$SRC" --out "$SET/$2" >/dev/null
}

# iOS marketing / single-size icon.
gen 1024 "icon-ios-1024.png"

# macOS icon ladder (16,32,128,256,512 at @1x and @2x).
gen 16   "icon-mac-16.png"
gen 32   "icon-mac-16@2x.png"
gen 32   "icon-mac-32.png"
gen 64   "icon-mac-32@2x.png"
gen 128  "icon-mac-128.png"
gen 256  "icon-mac-128@2x.png"
gen 256  "icon-mac-256.png"
gen 512  "icon-mac-256@2x.png"
gen 512  "icon-mac-512.png"
gen 1024 "icon-mac-512@2x.png"

cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "icon-ios-1024.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon-mac-16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon-mac-16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon-mac-32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon-mac-32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon-mac-128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon-mac-128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon-mac-256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon-mac-256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon-mac-512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon-mac-512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "==> Wrote $(ls "$SET" | wc -l | tr -d ' ') files to AppIcon.appiconset"
