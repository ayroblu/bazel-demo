#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname)" != Darwin ]]; then
  echo "Cannot run macOS targets on a non-mac machine." >&2
  exit 1
fi

readonly RUNFILES_DIR="${BASH_SOURCE[0]}.runfiles/_main"
readonly APP_DIR="${RUNFILES_DIR}/local-call-app/macos_app_archive-root/Local Call App.app"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "App bundle not found: ${APP_DIR}" >&2
  exit 1
fi

readonly BUNDLE_EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${APP_DIR}/Contents/Info.plist")
"${APP_DIR}/Contents/MacOS/${BUNDLE_EXECUTABLE}" "$@"
