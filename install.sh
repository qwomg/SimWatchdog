#!/bin/bash
# SimWatchdog installer: downloads the latest release, verifies its checksum, installs and opens it.
#   curl -fsSL https://raw.githubusercontent.com/qwomg/SimWatchdog/main/install.sh | bash
set -euo pipefail

BASE="https://github.com/qwomg/SimWatchdog/releases/latest/download"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading SimWatchdog..."
curl -fsSL "$BASE/SimWatchdog.zip" -o "$tmp/SimWatchdog.zip"
curl -fsSL "$BASE/SimWatchdog.zip.sha256" -o "$tmp/SimWatchdog.zip.sha256"

expected=$(awk '{print $1}' "$tmp/SimWatchdog.zip.sha256")
actual=$(shasum -a 256 "$tmp/SimWatchdog.zip" | awk '{print $1}')
if [ "$expected" != "$actual" ]; then
  echo "Checksum mismatch, aborting." >&2
  exit 1
fi

pkill -x SimWatchdog 2>/dev/null || true       # quit an older version if it is running
ditto -x -k "$tmp/SimWatchdog.zip" "$tmp"
rm -rf "$DEST/SimWatchdog.app"
mv "$tmp/SimWatchdog.app" "$DEST/SimWatchdog.app"
xattr -dr com.apple.quarantine "$DEST/SimWatchdog.app" 2>/dev/null || true

echo "Installed to $DEST/SimWatchdog.app"
open "$DEST/SimWatchdog.app"
