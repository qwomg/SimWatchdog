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

// MARK: - Per-app memory use

struct AppUse {
    let app: NSRunningApplication
    let name: String
    let bytes: UInt64
    var gb: String { String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }
}

enum Footprint {
    private static func parent(of pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? pid_t(info.pbi_ppid) : 0
    }

    private static func footprint(of pid: pid_t) -> UInt64 {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return status == 0 ? usage.ri_phys_footprint : 0
    }

    /// Memory footprint of every regular (Dock) app, including all its helper processes (browsers and
    /// Electron apps spread their memory over many child processes).
    static func appUsage() -> [AppUse] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let byPid = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var totals: [pid_t: UInt64] = [:]
        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            var root = pid
            var hops = 0
            while byPid[root] == nil, hops < 12 {
                let up = parent(of: root)
                if up <= 1 { break }
                root = up
                hops += 1
            }
            guard byPid[root] != nil else { continue }
            totals[root, default: 0] += footprint(of: pid)
        }
        return totals.compactMap { pid, bytes in
            guard let app = byPid[pid] else { return nil }
            return AppUse(app: app, name: app.localizedName ?? app.bundleIdentifier ?? "pid \(pid)", bytes: bytes)
        }
    }
}

// MARK: - Watchdog

final class Watchdog {
    /// Matches any running simulator (used to decide whether there is anything to close).
    static let simDetect = "Simulator.app/Contents/MacOS/Simulator|CoreSimulator/Devices|launchd_sim"
    /// Everything we force-kill once the graceful shutdown has had its few seconds.
    static let simKill = simDetect + "|SimLaunchHost|SimulatorTrampoline"
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    static let androidRegex = "(qemu-system[^ ]*|emulator[0-9]*) .*-avd"
    /// Never force-quit these, even if the user lists them.
    static let protectedApps: Set<String> = ["finder", "dock", "simwatchdog", "loginwindow", "systemuiserver"]

    private let settings = Settings.shared
    private let work = DispatchQueue(label: "simwatchdog.work")
    private var timer: Timer?
    private var strikes = 0
    private var cooldownUntil = Date.distantPast
    private var lastStatusLog = Date.distantPast

    var fakeLevel: Int?
    /// Test only (--only-app NAME): the "biggest apps" step may only ever pick this app.
    var onlyApp: String?
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

        // Leave a trail: a Mac that sits under pressure for hours is exactly what we want to see afterwards.
        if p.pressure >= 2, Date().timeIntervalSince(lastStatusLog) > 300 {
            lastStatusLog = Date()
            Log.write("STATUS memory available \(p.level)%, pressure level \(p.pressure)")
        }

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
        let bigApps = settings.quitBigApps && !manual
        let bigMin = UInt64(settings.bigAppMinMB) * 1_048_576
        let never = Set((settings.neverCloseNames).map { $0.lowercased() })
        let notify = settings.notify
        let dry = dryRun
        let only = onlyApp
        Log.write("\(manual ? "MANUAL" : "TRIGGER") memory available \(p.level)%, pressure level \(p.pressure)\(dry ? " (dry run)" : "")")

        work.async { [weak self] in
            var closed: [String] = []

            // Who is really using the memory? Always written to the log, whatever we end up closing.
            let usage = Footprint.appUsage().sorted { $0.bytes > $1.bytes }
            Log.write("TOP apps: " + usage.prefix(6).map { "\($0.name) \($0.gb)" }.joined(separator: ", "))

            if sims, run("/usr/bin/pgrep", ["-f", Watchdog.simDetect]).status == 0 {
                if !dry {
                    // Graceful shutdown first, but never wait long. xcrun refuses to run inside the App Sandbox
                    // (Mac App Store build), where we go straight to closing the processes.
                    if !Watchdog.isSandboxed { run("/usr/bin/xcrun", ["simctl", "shutdown", "all"], timeout: 4) }
                    run("/usr/bin/pkill", ["-9", "-f", Watchdog.simKill])
                }
                closed.append("Simulators")
            }
            if android, run("/usr/bin/pgrep", ["-f", Watchdog.androidRegex]).status == 0 {
                if !dry { run("/usr/bin/pkill", ["-9", "-f", Watchdog.androidRegex]) }
                closed.append("Android Emulator")
            }
            if !extras.isEmpty {
                let wanted = extras.map { $0.lowercased() }
                let victims = usage.filter { u in
                    let lower = u.name.lowercased()
                    return !Watchdog.protectedApps.contains(lower) && !never.contains(lower)
                        && (wanted.contains(lower) || wanted.contains((u.app.bundleIdentifier ?? "").lowercased()))
                }
                Watchdog.quit(victims.map { $0.app }, dry: dry)
                closed += victims.map { $0.name }
            }

            // Escalation: simulators and listed apps were not enough, so ask the biggest apps to quit.
            if bigApps {
                if !dry { Thread.sleep(forTimeInterval: 5) }                   // give the first steps time to work
                let again = self?.readNow() ?? p
                if self?.isLow(again) ?? true {
                    let myPid = ProcessInfo.processInfo.processIdentifier
                    let candidates = Footprint.appUsage().sorted { $0.bytes > $1.bytes }.filter { u in
                        let lower = u.name.lowercased()
                        if let only = only { return lower == only.lowercased() }
                        return u.bytes >= bigMin && u.app.processIdentifier != myPid
                            && !Watchdog.protectedApps.contains(lower) && !never.contains(lower)
                            && !never.contains((u.app.bundleIdentifier ?? "").lowercased())
                    }.prefix(2)
                    if !candidates.isEmpty {
                        Watchdog.quit(candidates.map { $0.app }, dry: dry)
                        closed += candidates.map { "\($0.name) (\($0.gb))" }
                    }
                }
            }

            DispatchQueue.main.async { self?.report(closed: closed, probe: p, manual: manual, notify: notify, dry: dry) }
        }
    }

    private func readNow() -> Probe { readProbe(fake: fakeLevel) }

    /// Asks apps to quit so they can save; whatever is still running after 8 seconds is force-quit.
    private static func quit(_ apps: [NSRunningApplication], dry: Bool) {
        guard !dry, !apps.isEmpty else { return }
        DispatchQueue.main.sync { apps.forEach { $0.terminate() } }
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if DispatchQueue.main.sync(execute: { apps.allSatisfy { $0.isTerminated } }) { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        DispatchQueue.main.sync { apps.filter { !$0.isTerminated }.forEach { $0.forceTerminate() } }
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
