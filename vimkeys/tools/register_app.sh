#!/usr/bin/env bash
set -euo pipefail

echo "WORKSPACE: $BUILD_WORKSPACE_DIRECTORY"

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

app=vimkeys/vimkeys.app
if [[ ! -d "$app" ]]; then
  echo "app bundle not found: $1" >&2
  exit 1
fi

"$lsregister" -f -R -trusted "$app"

if command -v pluginkit >/dev/null 2>&1; then
  pluginkit -m -A -p com.apple.Safari.web-extension | grep 'com.ayroblu.vimkeys.Extension' || true
fi

cat <<EOF
Registered $app with LaunchServices.
EOF
