# Store listing copy

Copy for a storefront page (website, Gumroad, Lemon Squeezy, or an app store if one ever becomes possible). Screenshots are in `store/screenshots/` (2880x1800, PNG, no alpha: an accepted Mac App Store size). Third-party product names (Claude Code, Codex, Cursor, ...) are deliberately NOT used here: app stores reject other companies' trademarks in metadata. They live in the README only.

## Name (max 30 characters)
SimWatchdog: Memory Guard

_The app's own name (menu bar, bundle) stays "SimWatchdog"; only the store listing name carries "Memory Guard" for search._

## Subtitle (max 30 characters)
Stop simulator memory crashes

## Promotional text (max 170 characters)
Running several simulators, builds or AI coding agents? SimWatchdog closes your simulators when memory runs low, so your Mac never has to restart.

## Keywords (max 100 characters, comma-separated)
memory,simulator,xcode,kernel panic,crash,RAM,watchdog,menu bar,developer,emulator,out of memory

## Description
Your Mac restarts "because of a problem" while you build and test? One common culprit is memory: a handful of iOS Simulators, Xcode, previews and parallel tests quietly eat all your RAM until macOS freezes or panics.

SimWatchdog lives in your menu bar and watches available memory. When it runs low, it shuts down your simulators for you, before the crash, so you keep your work.

BUILT FOR AI-ASSISTED DEVELOPMENT
Coding agents boot simulators to check their work, run builds in parallel and rarely clean up. SimWatchdog is the safety net: start it once and forget it. No integration needed.

HOW IT WORKS
- Reads macOS's own "memory available" figure every few seconds (about 0% CPU)
- Confirms a second time a few seconds later, so a brief spike never triggers it
- Shuts simulators down gracefully, force-closes what is left, and tells you what it did

YOU STAY IN CONTROL
- Choose the trigger level, from 5% to 40% available memory
- Choose how often it checks
- Choose what to close: iOS, watchOS, tvOS and visionOS simulators, the Android Emulator, or any apps you list
- One-click "Close Simulators & Apps Now", pause any time, full log
- Starts at login

PRIVATE BY DESIGN
No accounts, no network access, no analytics. Open source (MIT): read every line, or build it yourself.

Works on Apple Silicon and Intel Macs running macOS 13 or later.

## What's new (1.0.1)
Screenshot tooling and documentation. No behaviour changes.

## Category
Developer Tools

## Support / website URL
https://github.com/qwomg/SimWatchdog

## Screenshot captions (already baked into the images)
1. Never lose work to an out-of-memory crash.
2. Your limit. Your rules.
3. Built for AI-assisted coding.
4. Quiet until it matters.
