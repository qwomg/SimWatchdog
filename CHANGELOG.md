# Changelog

## 1.0.1
- Added `--snapshot-menu` (captures the real menu for screenshots) and a reproducible screenshot script (`tools/make-screenshots.sh`).
- Developer ID signing support in `build.sh` (`SIGN_IDENTITY=...`), release/notarization checklist in `docs/RELEASING.md`.
- Docs: Homebrew install, AI-assisted-coding guide, test notes, App Store explanation. No behaviour changes.

## 1.0.0
- First public release: menu bar memory watchdog that force-closes iOS/watchOS/tvOS/visionOS simulators when available memory runs low.
- Settings window: trigger level, check interval, critical-pressure trigger, Android Emulator, extra apps to force-quit, launch at login, notifications, menu bar display.
- Universal binary (Apple Silicon + Intel), macOS 13+, ad-hoc signed.
