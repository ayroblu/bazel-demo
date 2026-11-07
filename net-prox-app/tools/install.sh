#!/usr/bin/env bash
set -euo pipefail

zip="$PWD/net-prox-app/net-prox-app.zip"
app="$HOME/Applications/NetProxToggle.app"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

unzip -q "$zip" -d "$staging"

identity=$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)
codesign --force --sign "${identity:--}" "$staging/NetProxToggle.app"

pkill -x NetProxToggle || true
while pgrep -x NetProxToggle >/dev/null; do sleep 0.1; done
mkdir -p "$(dirname "$app")"
rm -rf "$app"
mv "$staging/NetProxToggle.app" "$app"
open "$app"
echo "Installed and opened $app"
