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

    private let d = UserDefaults.standard
    private let defaults: [String: Any] = [
        "threshold": 15,
        "interval": 10,
        "triggerOnCritical": true,
        "closeSimulators": true,
        "closeAndroidEmulator": false,
        "extraApps": "",
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
