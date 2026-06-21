#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ios-release.sh archive
  bash scripts/ios-release.sh testflight

Environment overrides:
  IOS_ARCHIVE_PATH
  IOS_EXPORT_PATH
  IOS_EXPORT_OPTIONS_PLIST
  APP_STORE_CONNECT_API_KEY_PATH
  APP_STORE_CONNECT_API_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

MODE="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/native/ios/App/App.xcodeproj"
SCHEME="App"
ARCHIVE_PATH="${IOS_ARCHIVE_PATH:-$ROOT_DIR/release/ios/Stemacle.xcarchive}"
EXPORT_PATH="${IOS_EXPORT_PATH:-$ROOT_DIR/release/ios/testflight-export}"
EXPORT_OPTIONS_PLIST="${IOS_EXPORT_OPTIONS_PLIST:-$ROOT_DIR/native/ios/testflight-export-options.plist}"

AUTH_ARGS=()
if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" || -n "${APP_STORE_CONNECT_API_KEY_ID:-}" || -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  if [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" || -z "${APP_STORE_CONNECT_API_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
    echo "App Store Connect API key auth requires APP_STORE_CONNECT_API_KEY_PATH, APP_STORE_CONNECT_API_KEY_ID, and APP_STORE_CONNECT_ISSUER_ID." >&2
    exit 1
  fi

  AUTH_ARGS=(
    -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH"
    -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID"
    -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
  )
fi

run_xcodebuild() {
  if ((${#AUTH_ARGS[@]})); then
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -packageAuthorizationProvider netrc \
      "${AUTH_ARGS[@]}" \
      "$@"
  else
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -packageAuthorizationProvider netrc \
      "$@"
  fi
}

archive_app() {
  npm run ios:sync
  mkdir -p "$(dirname "$ARCHIVE_PATH")"
  rm -rf "$ARCHIVE_PATH"

  run_xcodebuild \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive
}

upload_testflight() {
  archive_app
  rm -rf "$EXPORT_PATH"
  mkdir -p "$EXPORT_PATH"

  if ((${#AUTH_ARGS[@]})); then
    xcodebuild \
      "${AUTH_ARGS[@]}" \
      -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
      -allowProvisioningUpdates
  else
    xcodebuild \
      -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
      -allowProvisioningUpdates
  fi
}

case "$MODE" in
  archive)
    archive_app
    ;;
  testflight)
    upload_testflight
    ;;
  *)
    usage
    exit 1
    ;;
esac
