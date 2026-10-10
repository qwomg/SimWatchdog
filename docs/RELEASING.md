# Releasing SimWatchdog

## Free build (ad-hoc signed)

```bash
echo 1.0.1 > VERSION            # and add a CHANGELOG entry
./build.sh                      # build/SimWatchdog.zip + SimWatchdog.zip.sha256
git commit -am "Release 1.0.1" && git tag v1.0.1 && git push --tags
gh release create v1.0.1 build/SimWatchdog.zip build/SimWatchdog.zip.sha256 --title "SimWatchdog 1.0.1"
```

Then update the Homebrew cask in `qwomg/homebrew-tap` (`version` and `sha256` from `SimWatchdog.zip.sha256`).

## Notarized build (the paid one)

Needs a **"Developer ID Application"** certificate (Xcode > Settings > Apple Accounts > team > Manage Certificates > + > Developer ID Application; an Admin can create it) and notarization credentials stored once in the keychain, either with an App Store Connect API key (needs its Issuer ID) or an Apple ID app-specific password:

```bash
xcrun notarytool store-credentials simwatchdog-notary \
  --key ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-UUID>
```

Then one command builds, signs (hardened runtime + timestamp), notarizes, staples and verifies:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" tools/notarize.sh
# -> build/SimWatchdog-notarized.zip (+ .sha256). spctl must report: accepted, source=Notarized Developer ID
```

Signing with the Developer ID certificate has been verified (`codesign --verify --strict`, hardened runtime, secure timestamp). The notarization submission itself has not been run yet because it needs the credentials above.

## Mac App Store

Not possible for this app: the App Sandbox is mandatory there, and a sandboxed process cannot enumerate or signal other processes, which is the app's entire job (verified with a sandboxed test build).
