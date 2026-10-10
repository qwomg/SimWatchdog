import Cocoa

let args = CommandLine.arguments
func value(after flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let app = NSApplication.shared
let delegate = AppDelegate()
delegate.fakeLevel = value(after: "--fake-level").flatMap { Int($0) }
delegate.dryRun = args.contains("--dry-run")
delegate.snapshotPath = value(after: "--snapshot")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
