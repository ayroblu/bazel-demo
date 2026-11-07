#!/usr/bin/env bash
set -euo pipefail

zip="$PWD/net-prox/net-prox.zip"
app="$HOME/Applications/NetProx.app"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

unzip -q "$zip" -d "$staging"

identity=$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)
codesign --force --sign "${identity:--}" "$staging/NetProx.app"

pkill -x NetProx || true
while pgrep -x NetProx >/dev/null; do sleep 0.1; done
mkdir -p "$(dirname "$app")"
rm -rf "$app"
mv "$staging/NetProx.app" "$app"
open "$app"
echo "Installed and opened $app"
