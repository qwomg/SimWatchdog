import Cocoa
import ServiceManagement

/// Plain view that paints the standard window background (so it also renders correctly in snapshots).
private final class FlatView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

enum App {
    static let repoURL = "https://github.com/qwomg/SimWatchdog"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let s = Settings.shared

    private let slider = NSSlider(value: 15, minValue: Double(Settings.thresholdRange.lowerBound),
                                  maxValue: Double(Settings.thresholdRange.upperBound), target: nil, action: nil)
    private let sliderValue = NSTextField(labelWithString: "15%")
    private let intervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let extraField = NSTextField(string: "")
    private let neverField = NSTextField(string: "")
    private let bigAppPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var checks: [String: NSButton] = [:]

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SimWatchdog Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        loadValues()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: UI construction

    private func heading(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .boldSystemFont(ofSize: 13)
        return l
    }

    private func help(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 440
        return l
    }

    private func checkbox(_ key: String, _ title: String) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkChanged(_:)))
        b.identifier = NSUserInterfaceItemIdentifier(key)
        checks[key] = b
        return b
    }

    private func buildUI() {
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.widthAnchor.constraint(equalToConstant: 330).isActive = true
        sliderValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let sliderRow = NSStackView(views: [slider, sliderValue])
        sliderRow.spacing = 10

        for choice in Settings.intervalChoices { intervalPopup.addItem(withTitle: choice.label) }
        intervalPopup.target = self
        intervalPopup.action = #selector(intervalChanged)
        let intervalRow = NSStackView(views: [NSTextField(labelWithString: "Check memory every"), intervalPopup])
        intervalRow.spacing = 8

        extraField.placeholderString = "e.g. Google Chrome, Docker Desktop"
        extraField.delegate = self
        extraField.widthAnchor.constraint(equalToConstant: 440).isActive = true

        for choice in Settings.bigAppChoices { bigAppPopup.addItem(withTitle: choice.label) }
        bigAppPopup.target = self
        bigAppPopup.action = #selector(bigAppChanged)
        let bigRow = NSStackView(views: [NSTextField(labelWithString: "Only apps using more than"), bigAppPopup])
        bigRow.spacing = 8
        neverField.placeholderString = "e.g. Terminal, Xcode"
        neverField.delegate = self
        neverField.widthAnchor.constraint(equalToConstant: 440).isActive = true

        func column(_ apps: [Settings.KnownApp]) -> NSStackView {
            let col = NSStackView(views: apps.map { checkbox($0.key, $0.title) })
            col.orientation = .vertical
            col.alignment = .leading
            col.spacing = 6
            return col
        }
        let half = (Settings.knownApps.count + 1) / 2
        let protectRow = NSStackView(views: [column(Array(Settings.knownApps.prefix(half))),
                                             column(Array(Settings.knownApps.suffix(from: half)))])
        protectRow.orientation = .horizontal
        protectRow.alignment = .top
        protectRow.spacing = 24

        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetDefaults))
        let link = NSTextField(labelWithAttributedString: {
            let text = "SimWatchdog \(App.version)  ·  github.com/qwomg/SimWatchdog"
            let a = NSMutableAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
            a.addAttribute(.link, value: App.repoURL, range: (text as NSString).range(of: "github.com/qwomg/SimWatchdog"))
            return a
        }())
        link.allowsEditingTextAttributes = true
        link.isSelectable = true
        let footer = NSStackView(views: [reset, link])
        footer.spacing = 16

        let views: [NSView] = [
            heading("When to act"),
            NSTextField(labelWithString: "Close things when available memory drops to or below:"),
            sliderRow,
            help("This is the \"memory available\" figure macOS itself tracks (the free part of Activity Monitor's Memory Pressure graph). 15% is a good start: the Mac is struggling but not yet frozen."),
            intervalRow,
            help("It automatically checks every few seconds once memory gets low, whatever you pick here."),
            checkbox("triggerOnCritical", "Also act when macOS reports critical memory pressure"),

            heading("What to close"),
            checkbox("closeSimulators", "iOS, watchOS, tvOS and visionOS Simulators"),
            checkbox("closeAndroidEmulator", "Android Emulator"),
            NSTextField(labelWithString: "Also force-quit these apps (names, separated by commas):"),
            extraField,
            help("Force-quitting loses unsaved work in that app. Leave this empty unless you are sure."),
            checkbox("quitBigApps", "If memory is still critical, also quit the biggest apps"),
            bigRow,
            NSTextField(labelWithString: "Never close these apps (nothing is protected unless you tick it):"),
            protectRow,
            NSTextField(labelWithString: "Other apps to never close (names, separated by commas):"),
            neverField,
            help("Only automatic actions do this, never the menu's manual button. Apps are asked to quit first so they can save; any app still running after 8 seconds is force-quit and its unsaved work is lost. At most two apps per round. \"Simulator / Device Hub\" protects the Simulator app itself; the Simulators checkbox above controls closing simulators."),

            heading("General"),
            checkbox("launchAtLogin", "Launch at login (recommended: it can only protect you while it runs)"),
            checkbox("notify", "Show a notification when it closes something"),
            checkbox("showPercent", "Show the memory percentage in the menu bar"),
            checkbox("showIcon", "Show the menu bar icon (reopen the app to bring it back)"),
            footer,
        ]

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        for (i, v) in views.enumerated() where (v as? NSTextField)?.font == NSFont.boldSystemFont(ofSize: 13) && i > 0 {
            stack.setCustomSpacing(20, after: views[i - 1])
        }
        stack.setCustomSpacing(18, after: views[views.count - 2])
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = FlatView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 500),
        ])
        window?.contentView = content
        content.layoutSubtreeIfNeeded()
        window?.setContentSize(content.fittingSize)
    }

    // MARK: Values

    func loadValues() {
        slider.integerValue = s.threshold
        sliderValue.stringValue = "\(s.threshold)%"
        intervalPopup.selectItem(at: Settings.intervalChoices.firstIndex { $0.seconds == s.interval } ?? 1)
        extraField.stringValue = s.extraApps
        neverField.stringValue = s.neverCloseApps
        bigAppPopup.selectItem(at: Settings.bigAppChoices.firstIndex { $0.megabytes == s.bigAppMinMB } ?? 2)
        checks["quitBigApps"]?.state = s.quitBigApps ? .on : .off
        for app in Settings.knownApps { checks[app.key]?.state = s.isProtected(app.key) ? .on : .off }
        checks["triggerOnCritical"]?.state = s.triggerOnCritical ? .on : .off
        checks["closeSimulators"]?.state = s.closeSimulators ? .on : .off
        checks["closeAndroidEmulator"]?.state = s.closeAndroidEmulator ? .on : .off
        checks["notify"]?.state = s.notify ? .on : .off
        checks["showPercent"]?.state = s.showPercent ? .on : .off
        checks["showIcon"]?.state = s.showIcon ? .on : .off
        checks["launchAtLogin"]?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func show() {
        loadValues()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Actions

    @objc private func sliderChanged() {
        s.threshold = slider.integerValue
        sliderValue.stringValue = "\(s.threshold)%"
    }

    @objc private func intervalChanged() {
        s.interval = Settings.intervalChoices[max(intervalPopup.indexOfSelectedItem, 0)].seconds
    }

    @objc private func checkChanged(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender.identifier?.rawValue ?? "" {
        case "triggerOnCritical": s.triggerOnCritical = on
        case "closeSimulators": s.closeSimulators = on
        case "closeAndroidEmulator": s.closeAndroidEmulator = on
        case "quitBigApps": s.quitBigApps = on
        case "notify": s.notify = on
        case "showPercent": s.showPercent = on
        case "showIcon": s.showIcon = on
        case "launchAtLogin": setLaunchAtLogin(on)
        default:
            if Settings.knownApps.contains(where: { $0.key == sender.identifier?.rawValue }) {
                s.setProtected(sender.identifier!.rawValue, on)
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === neverField { s.neverCloseApps = neverField.stringValue } else { s.extraApps = extraField.stringValue }
    }

    @objc private func bigAppChanged() {
        s.bigAppMinMB = Settings.bigAppChoices[max(bigAppPopup.indexOfSelectedItem, 0)].megabytes
    }

    @objc private func resetDefaults() {
        s.resetToDefaults()
        loadValues()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can also add SimWatchdog yourself in System Settings > General > Login Items."
            alert.runModal()
        }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        loadValues()
    }

    // MARK: Snapshot (used to make the README screenshot)

    func snapshot(to path: String) {
        loadValues()
        guard let view = window?.contentView else { return }
        window?.appearance = NSAppearance(named: .aqua)
        view.layoutSubtreeIfNeeded()
        let scale = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(view.bounds.width) * scale, pixelsHigh: Int(view.bounds.height) * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
