#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ios-release.sh archive
  bash scripts/ios-release.sh testflight
  bash scripts/ios-release.sh publish
  bash scripts/ios-release.sh validate

Environment overrides:
  IOS_ARCHIVE_PATH
  IOS_EXPORT_PATH
  IOS_EXPORT_OPTIONS_PLIST
  IOS_UPLOAD_OPTIONS_PLIST
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
SCHEME="Stemacle"
ARCHIVE_PATH="${IOS_ARCHIVE_PATH:-$ROOT_DIR/release/ios/Stemacle.xcarchive}"
EXPORT_PATH="${IOS_EXPORT_PATH:-$ROOT_DIR/release/ios/testflight-export}"
EXPORT_OPTIONS_PLIST="${IOS_EXPORT_OPTIONS_PLIST:-$ROOT_DIR/native/ios/testflight-export-options.plist}"
UPLOAD_OPTIONS_PLIST="${IOS_UPLOAD_OPTIONS_PLIST:-$ROOT_DIR/native/ios/appstore-upload-options.plist}"

validate_release_inputs() {
  npm run appstore:verify

  if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
    echo "Missing export options plist: $EXPORT_OPTIONS_PLIST" >&2
    exit 1
  fi

  if [[ ! -f "$UPLOAD_OPTIONS_PLIST" ]]; then
    echo "Missing upload options plist: $UPLOAD_OPTIONS_PLIST" >&2
    exit 1
  fi

  if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" || -n "${APP_STORE_CONNECT_API_KEY_ID:-}" || -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
    if [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" || -z "${APP_STORE_CONNECT_API_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
      echo "App Store Connect API key auth requires APP_STORE_CONNECT_API_KEY_PATH, APP_STORE_CONNECT_API_KEY_ID, and APP_STORE_CONNECT_ISSUER_ID." >&2
      exit 1
    fi

    if [[ ! -f "$APP_STORE_CONNECT_API_KEY_PATH" ]]; then
      echo "Missing App Store Connect API key file: $APP_STORE_CONNECT_API_KEY_PATH" >&2
      exit 1
    fi
  fi
}

require_app_store_connect_auth() {
  if [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" && -z "${APP_STORE_CONNECT_API_KEY_ID:-}" && -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
    return 1
  fi

  if [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" || -z "${APP_STORE_CONNECT_API_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
    echo "App Store Connect API key auth requires APP_STORE_CONNECT_API_KEY_PATH, APP_STORE_CONNECT_API_KEY_ID, and APP_STORE_CONNECT_ISSUER_ID." >&2
    exit 1
  fi

  if [[ ! -f "$APP_STORE_CONNECT_API_KEY_PATH" ]]; then
    echo "Missing App Store Connect API key file: $APP_STORE_CONNECT_API_KEY_PATH" >&2
    exit 1
  fi

  return 0
}

AUTH_ARGS=()
if require_app_store_connect_auth; then
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

  # Keep the default flow as a local export so we can verify release packaging
  # without requiring App Store Connect upload credentials until the user is ready.
  if ((${#AUTH_ARGS[@]})); then
    xcodebuild \
      "${AUTH_ARGS[@]}" \
      -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
  else
    xcodebuild \
      -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
  fi
}

publish_testflight() {
  if ! require_app_store_connect_auth; then
    echo "App Store Connect API key auth is required for publish mode." >&2
    exit 1
  fi

  archive_app
  rm -rf "$EXPORT_PATH"
  mkdir -p "$EXPORT_PATH"

  xcodebuild \
    "${AUTH_ARGS[@]}" \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$UPLOAD_OPTIONS_PLIST" \
    -allowProvisioningUpdates
}

case "$MODE" in
  archive)
    archive_app
    ;;
  testflight)
    upload_testflight
    ;;
  publish)
    publish_testflight
    ;;
  validate)
    validate_release_inputs
    ;;
  *)
    usage
    exit 1
    ;;
esac
