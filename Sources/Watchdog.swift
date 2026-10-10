import Cocoa
import UserNotifications

// MARK: - Memory probe

struct Probe {
    /// Percent of memory macOS considers available (the same figure behind Activity Monitor's pressure graph).
    let level: Int
    /// 1 = normal, 2 = warning, 4 = critical (kern.memorystatus_vm_pressure_level).
    let pressure: Int
}

private func sysctlInt(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
}

func readProbe(fake: Int? = nil) -> Probe {
    if let fake = fake { return Probe(level: fake, pressure: 1) }
    return Probe(level: sysctlInt("kern.memorystatus_level") ?? 100,
                 pressure: sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1)
}

// MARK: - Helpers

/// Runs a tool and waits at most `timeout` seconds. Never blocks forever, because the machine is
/// usually in trouble when we call this.
@discardableResult
func run(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    let done = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in done.signal() }
    do { try p.run() } catch { return (-1, "") }
    if done.wait(timeout: .now() + timeout) == .timedOut {
        p.terminate()
        kill(p.processIdentifier, SIGKILL)
        return (-2, "")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SimWatchdog.log")
    private static let queue = DispatchQueue(label: "simwatchdog.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()

    static func write(_ message: String) {
        queue.async {
            let line = "\(formatter.string(from: Date())) \(message)\n"
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 512_000 {
                try? fm.removeItem(at: url)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            }
        }
    }
}

// MARK: - Watchdog

final class Watchdog {
    /// Matches any running simulator (used to decide whether there is anything to close).
    static let simDetect = "Simulator.app/Contents/MacOS/Simulator|CoreSimulator/Devices|launchd_sim"
    /// Everything we force-kill once the graceful shutdown has had its few seconds.
    static let simKill = simDetect + "|SimLaunchHost|SimulatorTrampoline"
    static let androidRegex = "(qemu-system[^ ]*|emulator[0-9]*) .*-avd"
    /// Never force-quit these, even if the user lists them.
    static let protectedApps: Set<String> = ["finder", "dock", "simwatchdog", "loginwindow", "systemuiserver"]

    private let settings = Settings.shared
    private let work = DispatchQueue(label: "simwatchdog.work")
    private var timer: Timer?
    private var strikes = 0
    private var cooldownUntil = Date.distantPast

    var fakeLevel: Int?
    var dryRun = false
    /// Called on the main thread after every probe.
    var onProbe: ((Probe) -> Void)?
    /// Called on the main thread after an action, with a one-line summary.
    var onAction: ((String) -> Void)?

    func start() { scheduleNext(after: 0.5) }

    /// Re-read settings (interval) right away.
    func settingsChanged() { scheduleNext(after: 0.5) }

    private func scheduleNext(after seconds: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.tick() }
        t.tolerance = min(seconds * 0.1, 1)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func isLow(_ p: Probe) -> Bool {
        p.level <= settings.threshold || (settings.triggerOnCritical && p.pressure >= 4)
    }

    private func tick() {
        let p = readProbe(fake: fakeLevel)
        onProbe?(p)
        var next = TimeInterval(settings.interval)

        if settings.paused {
            strikes = 0
        } else if isLow(p) {
            if Date() >= cooldownUntil {
                strikes += 1
                next = 3                              // confirm quickly: filters a momentary spike
                if strikes >= 2 {
                    strikes = 0
                    cooldownUntil = Date().addingTimeInterval(45)
                    act(p, manual: false)
                }
            } else {
                next = min(next, 10)
            }
        } else {
            strikes = 0
            // Getting close to the limit: watch more closely, whatever the interval is.
            if p.level <= settings.threshold + 10 { next = min(next, 5) }
        }
        scheduleNext(after: next)
    }

    // MARK: Acting

    func actNow() { act(readProbe(fake: fakeLevel), manual: true) }

    private func act(_ p: Probe, manual: Bool) {
        let sims = settings.closeSimulators
        let android = settings.closeAndroidEmulator
        let extras = settings.extraAppNames
        let notify = settings.notify
        let dry = dryRun
        Log.write("\(manual ? "MANUAL" : "TRIGGER") memory available \(p.level)%, pressure level \(p.pressure)\(dry ? " (dry run)" : "")")

        work.async { [weak self] in
            var closed: [String] = []

            if sims, run("/usr/bin/pgrep", ["-f", Watchdog.simDetect]).status == 0 {
                if !dry {
                    run("/usr/bin/xcrun", ["simctl", "shutdown", "all"], timeout: 4)   // graceful, but never wait long
                    run("/usr/bin/pkill", ["-9", "-f", Watchdog.simKill])
                }
                closed.append("Simulators")
            }
            if android, run("/usr/bin/pgrep", ["-f", Watchdog.androidRegex]).status == 0 {
                if !dry { run("/usr/bin/pkill", ["-9", "-f", Watchdog.androidRegex]) }
                closed.append("Android Emulator")
            }
            if !extras.isEmpty {
                closed += DispatchQueue.main.sync { Watchdog.forceQuit(names: extras, dry: dry) }
            }

            DispatchQueue.main.async { self?.report(closed: closed, probe: p, manual: manual, notify: notify, dry: dry) }
        }
    }

    private static func forceQuit(names: [String], dry: Bool) -> [String] {
        var quit: [String] = []
        let wanted = names.map { $0.lowercased() }
        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { continue }
            let name = app.localizedName ?? ""
            let lower = name.lowercased()
            guard !protectedApps.contains(lower), wanted.contains(lower) || wanted.contains((app.bundleIdentifier ?? "").lowercased()) else { continue }
            if !dry { app.forceTerminate() }
            quit.append(name)
        }
        return quit
    }

    private func report(closed: [String], probe: Probe, manual: Bool, notify: Bool, dry: Bool) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let what = closed.isEmpty ? "nothing to close" : "closed " + closed.joined(separator: ", ")
        let line = "\(time): \(dry ? "[dry run] " : "")\(what) (memory \(probe.level)%)"
        settings.lastAction = line
        Log.write("RESULT \(what)")
        onAction?(line)

        guard notify, !dry, !closed.isEmpty || manual else { return }
        let content = UNMutableNotificationContent()
        content.title = closed.isEmpty ? "Nothing to close" : "SimWatchdog freed memory"
        content.body = closed.isEmpty
            ? "No simulators or selected apps were running."
            : "Available memory was down to \(probe.level)%. Closed: \(closed.joined(separator: ", "))."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
