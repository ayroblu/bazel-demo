#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname)" != Darwin ]]; then
  echo "Cannot run macOS targets on a non-mac machine." >&2
  exit 1
fi

readonly RUNFILES_DIR="${BASH_SOURCE[0]}.runfiles/_main"
readonly APP_ZIP="${RUNFILES_DIR}/language-app/macos-app.zip"
readonly APP_DIR="${TMPDIR:-/tmp}/language-app-${UID}/Language App.app"

if [[ ! -f "${APP_ZIP}" ]]; then
  echo "App archive not found: ${APP_ZIP}" >&2
  exit 1
fi

rm -rf "${APP_DIR%/*}"
mkdir -p "${APP_DIR%/*}"
ditto -x -k "${APP_ZIP}" "${APP_DIR%/*}"

readonly BUNDLE_EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${APP_DIR}/Contents/Info.plist")
"${APP_DIR}/Contents/MacOS/${BUNDLE_EXECUTABLE}" "$@"
