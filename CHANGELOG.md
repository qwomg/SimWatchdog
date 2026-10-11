# Changelog

## 1.2.0
- "Quit the biggest apps when memory is still critical" is now **on by default**.
- New "Never close" switches, one per well-known app: Claude desktop app, Claude Code CLI (terminal apps), ChatGPT / Codex, Google Chrome, Simulator / Device Hub, Xcode. **All off by default**: nothing is protected unless the user ticks it. The free-text "other apps" list stays.
- First-run welcome text explains the biggest-apps step.

## 1.1.0
- New, opt-in escalation: if memory is still critical after simulators and listed apps are closed, ask the biggest apps to quit (force-quit after 8 s). Settings: on/off, minimum size, a "never close" list. At most 2 apps per round.
- The log now records the top memory-using apps at every trigger (`TOP apps:`) and a `STATUS` line every 5 minutes while macOS reports memory pressure.
- Apps you list under "force-quit" are now asked to quit first and only force-quit after 8 seconds.
- Support flags: `--login-status` and `--enable-login` for the Launch at login item.
- Why: a real overnight freeze on a 36 GB Mac where ChatGPT, Claude and Chrome used about 28 GB and no simulator was running. macOS reported 42% memory available at the moment pressure turned critical.

## 1.0.1
- Added `--snapshot-menu` (captures the real menu for screenshots) and a reproducible screenshot script (`tools/make-screenshots.sh`).
- Developer ID signing support in `build.sh` (`SIGN_IDENTITY=...`), release/notarization checklist in `docs/RELEASING.md`.
- Docs: Homebrew install, AI-assisted-coding guide, test notes, App Store explanation. No behaviour changes.

## 1.0.0
- First public release: menu bar memory watchdog that force-closes iOS/watchOS/tvOS/visionOS simulators when available memory runs low.
- Settings window: trigger level, check interval, critical-pressure trigger, Android Emulator, extra apps to force-quit, launch at login, notifications, menu bar display.
- Universal binary (Apple Silicon + Intel), macOS 13+, ad-hoc signed.
