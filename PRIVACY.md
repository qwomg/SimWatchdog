# SimWatchdog Privacy Policy

_Last updated: 10 October 2026_

SimWatchdog does not collect, store, transmit or share any personal data.

- **No network access.** The app makes no network connections. It has no accounts, no analytics, no advertising and no third-party SDKs.
- **What it reads.** Two memory values from macOS (how much memory is available, and the system's memory-pressure level), and the list of running processes, only to find iOS Simulators, the Android Emulator, and any app names you typed into Settings.
- **What it stores.** Your settings (stored by macOS on your Mac) and a small activity log on your Mac (`~/Library/Logs/SimWatchdog.log`, or inside the app's container for the Mac App Store version). Nothing leaves your computer.
- **What it does.** When available memory is low it closes simulators (and anything you chose in Settings). It does nothing else.

SimWatchdog is open source (MIT): you can read exactly what it does at https://github.com/qwomg/SimWatchdog.

Questions: open an issue at https://github.com/qwomg/SimWatchdog/issues.
