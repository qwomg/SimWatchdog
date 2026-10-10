#!/bin/bash
# Builds a Developer-ID-signed SimWatchdog, notarizes it with Apple, staples the ticket and writes
# build/SimWatchdog-notarized.zip (+ .sha256). Not for the public free release: this is the paid build.
#
# One-time setup (stores credentials in your login keychain, nothing is written to the repo):
#   xcrun notarytool store-credentials simwatchdog-notary \
#     --key ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-UUID>
#   (or: --apple-id you@example.com --team-id TEAMID --password <app-specific-password>)
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" tools/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?set SIGN_IDENTITY to your Developer ID Application identity}"
PROFILE="${NOTARY_PROFILE:-simwatchdog-notary}"

./build.sh
xcrun notarytool submit build/SimWatchdog.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/SimWatchdog.app
xcrun stapler validate build/SimWatchdog.app
spctl --assess --type execute --verbose=2 build/SimWatchdog.app   # expect: accepted, source=Notarized Developer ID

(cd build && rm -f SimWatchdog.zip SimWatchdog.zip.sha256 \
  && ditto -c -k --keepParent SimWatchdog.app SimWatchdog-notarized.zip \
  && shasum -a 256 SimWatchdog-notarized.zip > SimWatchdog-notarized.zip.sha256)
echo "Notarized build: build/SimWatchdog-notarized.zip"
