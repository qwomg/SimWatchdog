import Cocoa
import ServiceManagement

let args = CommandLine.arguments
func value(after flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

if args.contains("--login-status") || args.contains("--enable-login") {
    // Support flags: report (or enable) the "Launch at login" item without opening any UI.
    if args.contains("--enable-login") { try? SMAppService.mainApp.register() }
    let status = SMAppService.mainApp.status
    print("launch-at-login:", status == .enabled ? "enabled" : status == .requiresApproval ? "requires approval in System Settings > Login Items" : "not enabled")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
delegate.fakeLevel = value(after: "--fake-level").flatMap { Int($0) }
delegate.dryRun = args.contains("--dry-run")
delegate.snapshotPath = value(after: "--snapshot")
delegate.menuSnapshotPath = value(after: "--snapshot-menu")
delegate.appearanceName = value(after: "--appearance")
delegate.onlyApp = value(after: "--only-app")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
