#!/usr/bin/env bash
# Builds a Buggy.app bundle. Screen Recording and Accessibility permissions are
# granted to the bundle, so this is the binary to open on a Mac.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Buggy.app can only be built on macOS." >&2
  exit 1
fi

swift build -c release --product Buggy
APP="dist/Buggy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/Buggy" "$APP/Contents/MacOS/Buggy"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/Buggy"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP"
fi

echo "Built $APP"
echo "Open it with: open dist/Buggy.app"
