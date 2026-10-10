# Releasing SimWatchdog

## Free build (ad-hoc signed)

```bash
echo 1.0.1 > VERSION            # and add a CHANGELOG entry
./build.sh                      # build/SimWatchdog.zip + SimWatchdog.zip.sha256
git commit -am "Release 1.0.1" && git tag v1.0.1 && git push --tags
gh release create v1.0.1 build/SimWatchdog.zip build/SimWatchdog.zip.sha256 --title "SimWatchdog 1.0.1"
```

Then update the Homebrew cask in `qwomg/homebrew-tap` (`version` and `sha256` from `SimWatchdog.zip.sha256`).

## Notarized build (needs an Apple Developer ID certificate)

The notarized build is the one that opens without any Gatekeeper warning. You need a **"Developer ID Application"** certificate (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application, Account Holder only) and notarization credentials stored once in the keychain:

```bash
xcrun notarytool store-credentials "simwatchdog-notary" --apple-id YOU@EXAMPLE.COM --team-id TEAMID --password APP-SPECIFIC-PASSWORD
```

Then:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh      # hardened runtime + timestamp
xcrun notarytool submit build/SimWatchdog.zip --keychain-profile "simwatchdog-notary" --wait
xcrun stapler staple build/SimWatchdog.app
(cd build && rm SimWatchdog.zip && ditto -c -k --keepParent SimWatchdog.app SimWatchdog.zip && shasum -a 256 SimWatchdog.zip > SimWatchdog.zip.sha256)
spctl --assess --type execute --verbose build/SimWatchdog.app                # should say: accepted, source=Notarized Developer ID
```

These notarization steps have not been run yet (no Developer ID certificate was available when this was written), so treat them as a checklist and verify the `spctl` result.

## Mac App Store

Not possible for this app: the App Sandbox is mandatory there, and a sandboxed process cannot enumerate or signal other processes, which is the app's entire job (verified with a sandboxed test build).
