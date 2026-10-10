#!/bin/bash
# Builds build/SimWatchdog.app (universal arm64 + x86_64, ad-hoc signed) and build/SimWatchdog.zip
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
APP=build/SimWatchdog.app

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" Sources/*.swift -o "build/SimWatchdog-$arch"
done
lipo -create build/SimWatchdog-arm64 build/SimWatchdog-x86_64 -output "$APP/Contents/MacOS/SimWatchdog"
rm build/SimWatchdog-arm64 build/SimWatchdog-x86_64

sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signed by default. For a notarizable build: SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
if [ "${SIGN_IDENTITY:--}" = "-" ]; then
  codesign --force --sign - --identifier io.github.qwomg.SimWatchdog "$APP"
else
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --identifier io.github.qwomg.SimWatchdog "$APP"
fi

(cd build && ditto -c -k --keepParent SimWatchdog.app SimWatchdog.zip && shasum -a 256 SimWatchdog.zip > SimWatchdog.zip.sha256)
echo "Built $APP ($VERSION)"; lipo -info "$APP/Contents/MacOS/SimWatchdog"
