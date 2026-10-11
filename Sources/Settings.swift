import Foundation

extension Notification.Name {
    static let settingsChanged = Notification.Name("SimWatchdogSettingsChanged")
}

/// All user-facing preferences, stored in UserDefaults and applied live.
final class Settings {
    static let shared = Settings()

    static let intervalChoices: [(label: String, seconds: Int)] = [
        ("5 seconds", 5), ("10 seconds", 10), ("30 seconds", 30), ("1 minute", 60), ("5 minutes", 300),
    ]
    static let thresholdRange = 5...40
    static let bigAppChoices: [(label: String, megabytes: Int)] = [
        ("1 GB", 1024), ("2 GB", 2048), ("3 GB", 3072), ("4 GB", 4096), ("6 GB", 6144), ("8 GB", 8192),
    ]

    /// Well-known apps the user can protect with one switch. Matching is by app name or bundle identifier.
    struct KnownApp {
        let key: String
        let title: String
        let names: [String]
    }
    static let knownApps: [KnownApp] = [
        KnownApp(key: "protectClaudeDesktop", title: "Claude desktop app",
                 names: ["Claude", "com.anthropic.claudefordesktop"]),
        KnownApp(key: "protectClaudeCode", title: "Claude Code CLI (terminal apps)",
                 names: ["Terminal", "iTerm2", "iTerm", "Ghostty", "Warp", "kitty", "Alacritty", "WezTerm", "Hyper", "Tabby",
                         "com.apple.Terminal", "com.googlecode.iterm2"]),
        KnownApp(key: "protectChatGPT", title: "ChatGPT / Codex",
                 names: ["ChatGPT", "Codex", "com.openai.chat"]),
        KnownApp(key: "protectChrome", title: "Google Chrome",
                 names: ["Google Chrome", "Google Chrome Beta", "Google Chrome Canary", "com.google.Chrome"]),
        KnownApp(key: "protectSimulator", title: "Simulator / Device Hub",
                 names: ["Simulator", "Device Hub", "com.apple.iphonesimulator"]),
        KnownApp(key: "protectXcode", title: "Xcode",
                 names: ["Xcode", "Xcode-beta", "com.apple.dt.Xcode"]),
    ]

    private let d = UserDefaults.standard
    private let defaults: [String: Any] = [
        "threshold": 15,
        "interval": 10,
        "triggerOnCritical": true,
        "closeSimulators": true,
        "closeAndroidEmulator": false,
        "extraApps": "",
        "quitBigApps": true,                // on by default: nothing is protected until the user opts in
        "protectClaudeDesktop": false,
        "protectClaudeCode": false,
        "protectChatGPT": false,
        "protectChrome": false,
        "protectSimulator": false,
        "protectXcode": false,
        "bigAppMinMB": 3072,
        "neverCloseApps": "",
        "notify": true,
        "showPercent": true,
        "showIcon": true,
        "paused": false,
    ]

    private init() { d.register(defaults: defaults) }

    private func store(_ value: Any?, _ key: String) {
        d.set(value, forKey: key)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    /// Act when "memory available" (percent) is at or below this.
    var threshold: Int {
        get { min(max(d.integer(forKey: "threshold"), Settings.thresholdRange.lowerBound), Settings.thresholdRange.upperBound) }
        set { store(newValue, "threshold") }
    }
    /// Seconds between checks while memory is healthy.
    var interval: Int {
        get { max(d.integer(forKey: "interval"), 2) }
        set { store(newValue, "interval") }
    }
    var triggerOnCritical: Bool {
        get { d.bool(forKey: "triggerOnCritical") }
        set { store(newValue, "triggerOnCritical") }
    }
    var closeSimulators: Bool {
        get { d.bool(forKey: "closeSimulators") }
        set { store(newValue, "closeSimulators") }
    }
    var closeAndroidEmulator: Bool {
        get { d.bool(forKey: "closeAndroidEmulator") }
        set { store(newValue, "closeAndroidEmulator") }
    }
    /// Comma-separated app names to force-quit as well.
    var extraApps: String {
        get { d.string(forKey: "extraApps") ?? "" }
        set { store(newValue, "extraApps") }
    }
    var extraAppNames: [String] {
        extraApps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    /// When pressure stays critical after simulators/listed apps are closed, also quit the biggest apps.
    var quitBigApps: Bool {
        get { d.bool(forKey: "quitBigApps") }
        set { store(newValue, "quitBigApps") }
    }
    /// Only apps whose total memory footprint is above this are candidates.
    var bigAppMinMB: Int {
        get { max(d.integer(forKey: "bigAppMinMB"), 256) }
        set { store(newValue, "bigAppMinMB") }
    }
    /// Comma-separated app names that are never closed automatically.
    var neverCloseApps: String {
        get { d.string(forKey: "neverCloseApps") ?? "" }
        set { store(newValue, "neverCloseApps") }
    }
    func isProtected(_ key: String) -> Bool { d.bool(forKey: key) }
    func setProtected(_ key: String, _ value: Bool) { store(value, key) }

    /// Everything that must never be closed automatically: the switched-on known apps plus the free-text list.
    var neverCloseNames: [String] {
        let typed = neverCloseApps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let known = Settings.knownApps.filter { isProtected($0.key) }.flatMap { $0.names }
        return typed + known
    }
    var notify: Bool {
        get { d.bool(forKey: "notify") }
        set { store(newValue, "notify") }
    }
    var showPercent: Bool {
        get { d.bool(forKey: "showPercent") }
        set { store(newValue, "showPercent") }
    }
    var showIcon: Bool {
        get { d.bool(forKey: "showIcon") }
        set { store(newValue, "showIcon") }
    }
    var paused: Bool {
        get { d.bool(forKey: "paused") }
        set { store(newValue, "paused") }
    }
    var lastAction: String? {
        get { d.string(forKey: "lastAction") }
        set { d.set(newValue, forKey: "lastAction") }
    }

    func resetToDefaults() {
        for key in defaults.keys { d.removeObject(forKey: key) }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
