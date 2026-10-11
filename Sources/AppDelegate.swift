import Cocoa
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let settings = Settings.shared
    private let watchdog = Watchdog()
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem!
    private var lastProbe = readProbe()

    private let memoryItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let ruleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lastItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Watchdog", action: #selector(togglePause), keyEquivalent: "")

    // Test hooks (see README, "Testing"): --fake-level N  --dry-run  --snapshot file.png
    var fakeLevel: Int?
    var dryRun = false
    var snapshotPath: String?
    var menuSnapshotPath: String?      // --snapshot-menu out.png [--appearance dark|light]
    var appearanceName: String?
    var onlyApp: String?               // --only-app NAME: restrict the "biggest apps" step to one app (tests)
    private var isTestRun: Bool { fakeLevel != nil || dryRun || snapshotPath != nil || menuSnapshotPath != nil || onlyApp != nil }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = snapshotPath {
            SettingsWindowController().snapshot(to: path)
            exit(0)
        }
        if !isTestRun, let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate()          // already running: don't start a second watchdog
            exit(0)
        }

        installMainMenu()
        buildStatusItem()
        UNUserNotificationCenter.current().delegate = self
        if settings.notify { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }

        watchdog.fakeLevel = fakeLevel
        watchdog.dryRun = dryRun
        watchdog.onlyApp = onlyApp
        watchdog.onProbe = { [weak self] probe in self?.update(probe) }
        watchdog.onAction = { [weak self] _ in self?.refreshMenu() }
        NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.settingsDidChange()
        }
        watchdog.start()
        Log.write("started v\(App.version) (threshold \(settings.threshold)%, every \(settings.interval)s)")

        if !isTestRun { firstRunOnboarding() }
        if let path = menuSnapshotPath { captureMenu(to: path) }
    }

    // MARK: Screenshot support (opens the real menu and captures our own windows; needs no screen-recording permission)

    private func captureMenu(to path: String) {
        if let name = appearanceName { NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.statusItem.button?.performClick(nil) }
        let t = Timer(timeInterval: 1.8, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let pid = Int(ProcessInfo.processInfo.processIdentifier)
            let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
            let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int ?? 0) >= 100 }
            let menuWindow = mine.max { a, b in
                func area(_ w: [String: Any]) -> CGFloat {
                    let r = CGRect(dictionaryRepresentation: w[kCGWindowBounds as String] as! CFDictionary) ?? .zero
                    return r.width * r.height
                }
                return area(a) < area(b)
            }
            typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
            if let id = menuWindow?[kCGWindowNumber as String] as? UInt32,
               let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {   // RTLD_DEFAULT
                let capture = unsafeBitCast(sym, to: Capture.self)
                if let image = capture(.null, 8, id, 9)?.takeRetainedValue() {      // IncludingWindow, IgnoreFraming | BestResolution
                    let rep = NSBitmapImageRep(cgImage: image)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
            }
            self.statusItem.menu?.cancelTracking()
            exit(0)
        }
        RunLoop.main.add(t, forMode: .common)
    }

    /// Opening the app again (Finder, Spotlight) always brings up Settings, which is also how to get the icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "SimWatchdog")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        for item in [memoryItem, ruleItem, lastItem] { item.isEnabled = false; menu.addItem(item) }
        menu.addItem(.separator())
        menu.addItem(item("Close Simulators & Apps Now", #selector(closeNow), "k"))
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), ","))
        menu.addItem(item("Show Log", #selector(showLog), "l"))
        menu.addItem(item("About SimWatchdog on GitHub", #selector(openRepo), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit SimWatchdog (stops protection)", #selector(quit), "q"))
        statusItem.menu = menu
        applyAppearance()
        refreshMenu()
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func update(_ probe: Probe) {
        lastProbe = probe
        applyAppearance()
    }

    private func applyAppearance() {
        statusItem.isVisible = settings.showIcon
        guard let button = statusItem.button else { return }
        let near = lastProbe.level <= settings.threshold + 10
        var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
        if near && !settings.paused { attrs[.foregroundColor] = NSColor.systemRed }
        button.attributedTitle = NSAttributedString(string: settings.showPercent ? " \(lastProbe.level)%" : "", attributes: attrs)
        button.contentTintColor = (near && !settings.paused) ? .systemRed : nil
        button.appearsDisabled = settings.paused
        button.toolTip = "SimWatchdog: \(lastProbe.level)% memory available"
    }

    private func settingsDidChange() {
        applyAppearance()
        refreshMenu()
        watchdog.settingsChanged()
        if settings.notify { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        lastProbe = readProbe(fake: fakeLevel)
        refreshMenu()
    }

    private func refreshMenu() {
        memoryItem.title = "Memory available: \(lastProbe.level)%"
        var targets: [String] = []
        if settings.closeSimulators { targets.append("Simulators") }
        if settings.closeAndroidEmulator { targets.append("Android Emulator") }
        if settings.quitBigApps { targets.append("the biggest apps if critical") }
        if !settings.extraAppNames.isEmpty { targets.append("\(settings.extraAppNames.count) other app\(settings.extraAppNames.count == 1 ? "" : "s")") }
        ruleItem.title = targets.isEmpty
            ? "Nothing selected to close (see Settings)"
            : "Closes \(targets.joined(separator: ", ")) at \(settings.threshold)% or less"
        lastItem.title = settings.lastAction.map { "Last action: \($0)" } ?? "No action taken yet"
        pauseItem.state = settings.paused ? .on : .off
        pauseItem.title = settings.paused ? "Watchdog Paused (click to resume)" : "Pause Watchdog"
    }

    // MARK: Actions

    @objc private func closeNow() { watchdog.actNow() }

    @objc private func togglePause() { settings.paused.toggle() }

    @objc func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        if !settings.showIcon { settings.showIcon = true }     // opening the app again also brings the icon back
        settingsWindow?.show()
    }

    @objc private func showLog() {
        if !FileManager.default.fileExists(atPath: Log.url.path) { FileManager.default.createFile(atPath: Log.url.path, contents: nil) }
        NSWorkspace.shared.open(Log.url)
    }

    @objc private func openRepo() { NSWorkspace.shared.open(URL(string: App.repoURL)!) }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: First run

    private func firstRunOnboarding() {
        let key = "didOnboard"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SimWatchdog is running"
        alert.informativeText = "It lives in your menu bar and checks memory in the background. If your Mac gets close to running out of memory, it force-closes iOS Simulators first, so macOS never has to crash or restart.\n\nStart it automatically when you log in? It can only protect you while it is running."
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { try? SMAppService.mainApp.register() }
    }

    // MARK: Main menu (needed so Cmd-C / Cmd-V work in the Settings text field)

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit SimWatchdog", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }
}
