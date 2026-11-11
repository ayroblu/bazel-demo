#!/usr/bin/env bash
set -euo pipefail

zip="$PWD/alt-tab-app/alt-tab-app.zip"
app="$HOME/Applications/AltTab.app"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

unzip -q "$zip" -d "$staging"

identity=$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)
codesign --force --deep --sign "${identity:--}" "$staging/AltTab.app"

pkill -x AltTab || true
while pgrep -x AltTab >/dev/null; do sleep 0.1; done
mkdir -p "$(dirname "$app")"
rm -rf "$app"
mv "$staging/AltTab.app" "$app"
open "$app"
echo "Installed and opened $app"
