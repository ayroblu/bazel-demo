#!/usr/bin/env bash
set -euo pipefail

echo "WORKSPACE: $BUILD_WORKSPACE_DIRECTORY"

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

zip="vimkeys/vimkeys.zip"
if [[ ! -f "$zip" ]]; then
  echo "app zip not found: $zip" >&2
  exit 1
fi

# Unzip into the workspace so the registered app lives at a stable path that
# survives bazel output changes.
app_dir="$BUILD_WORKSPACE_DIRECTORY/vimkeys"
rm -rf "$app_dir/vimkeys.app"
unzip -o -q "$zip" -d "$app_dir"
app="$app_dir/vimkeys.app"

"$lsregister" -f -R -trusted "$app"

if command -v pluginkit >/dev/null 2>&1; then
  pluginkit -m -A -p com.apple.Safari.web-extension | grep 'com.ayroblu.vimkeys.Extension' || true
fi

cat <<EOF
Registered $app with LaunchServices.
EOF
