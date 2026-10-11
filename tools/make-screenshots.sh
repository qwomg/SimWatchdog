#!/bin/bash
# Regenerates store/screenshots/*.png (2880x1800) and docs/*.jpg from the REAL app. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=build/SimWatchdog.app/Contents/MacOS/SimWatchdog
T=$(mktemp -d)
LAST="10:42 AM: closed Simulators (memory 12%)"
"$BIN" --snapshot "$T/settings.png" -neverCloseApps ""   # clean defaults, not the developer's own list
"$BIN" --snapshot-menu "$T/menu.png"     --appearance dark --fake-level 62 -lastAction "$LAST"
"$BIN" --snapshot-menu "$T/menu-low.png" --appearance dark --fake-level 14 -lastAction "$LAST"
swiftc tools/compose-screenshots.swift -o "$T/compose"
mkdir -p store/screenshots
"$T/compose" "$T/menu.png" "$T/settings.png" "$T/menu-low.png" store/screenshots
for f in store/screenshots/*.png; do
  sips -Z 1440 -s format jpeg -s formatOptions 82 "$f" --out "docs/$(basename "$f" .png).jpg" >/dev/null
done
cp "$T/settings.png" docs/settings.png
echo "done"
