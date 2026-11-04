#!/usr/bin/env bash
set -euo pipefail

zip="$PWD/sherlock-app/sherlock-app.zip"
app="$HOME/Applications/Sherlock.app"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

unzip -q "$zip" -d "$staging"

identity=$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)
codesign --force --sign "${identity:--}" "$staging/Sherlock.app"

pkill -x Sherlock || true
mkdir -p "$(dirname "$app")"
rm -rf "$app"
mv "$staging/Sherlock.app" "$app"
open "$app"
echo "Installed and opened $app"
