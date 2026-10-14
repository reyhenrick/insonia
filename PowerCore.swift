import AppKit
import Combine
import Foundation

private let agentLabel = "com.henrick.insonia"

final class PowerCore: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var applying = false
    @Published private(set) var activeSince: Date?
    @Published private(set) var activateOnLaunch: Bool
    @Published private(set) var openAtLogin: Bool
    @Published private(set) var agentsEnabled: Bool
    @Published private(set) var status = L10n.text("status.normal")
    @Published private(set) var lastError: String?
    @Published private(set) var helperNeeded = !MacState.helperReady
    @Published private(set) var installingHelper = false
    @Published private(set) var guardianReady = false
    @Published private(set) var repairingGuardian = false
    @Published private(set) var recoveryNotice: RecoveryNotice?

    private let preferences = UserDefaults.standard
    private let runtime = RuntimeStore()
    private let brightness = DisplayBrightness()
    private lazy var coordinator = SessionCoordinator(store: runtime, brightness: brightness)
    private let displayActivity = DisplayActivity()
    private let sessionActivity = SessionActivity()
    private var lease: SessionLease?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var applyingSince: TimeInterval = 0
    private var lastRenewal: TimeInterval = -.infinity
    private var previousLid: Bool?
    private var screenLocked = false
    private var displayPaused = false
    private var started = false
    private var pendingAutostart = false
    private var stopRequestedAt: TimeInterval?
    private var helperProcess: Process?
    private var nextGuardianRetry: TimeInterval = 0
    private var guardianRetryDelay: TimeInterval = 15
    private var guardianInstallError: String?

    init() {
        activateOnLaunch = preferences.bool(forKey: "activateOnLaunch")
        openAtLogin = FileManager.default.fileExists(atPath: Self.agentPath)
        agentsEnabled = preferences.bool(forKey: "agentsEnabled")
    }

    var installedInApplications: Bool {
        let parent = Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().path
        return parent == "/Applications" || parent == NSHomeDirectory() + "/Applications"
    }

    var protectionInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.henrick.insonia.helper.plist")
    }

    func start(resumeActive: Bool = false) {
        guard !started else { return }
        guard installedInApplications else { lastError = L10n.text("error.installLocation"); return }
        started = true
        do {
            try runtime.prepare()
            if openAtLogin { try configureOpenAtLogin(true) }
        }
        catch { lastError = InsoniaFailure.wrapping(error).message }
        repairGuardian()
        observeSession()
        pendingAutostart = resumeActive || activateOnLaunch
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    func toggle() { setActive(!(active || applying)) }

    func setActive(_ on: Bool) {
        if !on { stop(); return }
        guard lease == nil, !installingHelper, !repairingGuardian else { return }
        guard installedInApplications else { lastError = L10n.text("error.installLocation"); return }
        lastError = nil
        helperNeeded = !MacState.helperReady
        guard !helperNeeded else {
            lastError = L10n.text("error.helperRequired")
            return
        }
        let health = GuardianManager.health(store: runtime)
        guard health.ready else {
            lastError = health.failure?.message ?? L10n.text("error.guardianStarting")
            return
        }
        if let reason = MacState.safety.stopReason { lastError = reason.message; return }
        guard MacState.lidClosed != nil else { lastError = L10n.text("error.lidUnknown"); return }
        if agentsEnabled {
            guard MacState.sessionAvailable, !screenLocked, DisplayBrightness.usableDisplay else {
                lastError = L10n.text("error.unlockToStart")
                return
            }
            do { _ = try brightness.snapshot() }
            catch { lastError = error.localizedDescription; return }
        }
        do {
            sessionActivity.start()
            lease = try coordinator.begin(mode: agentsEnabled ? .agents : .background)
            recoveryNotice = nil
            applying = true
            applyingSince = ProcessInfo.processInfo.systemUptime
            lastRenewal = -.infinity
            stopRequestedAt = nil
            previousLid = nil
            displayPaused = false
            status = L10n.text("status.confirming")
        } catch { sessionActivity.stop(); lastError = InsoniaFailure.wrapping(error).message }
    }

    func setAgentsEnabled(_ on: Bool) {
        if on {
            guard MacState.sessionAvailable, !screenLocked, DisplayBrightness.usableDisplay else {
                lastError = L10n.text("error.unlockForAgents")
                return
            }
            do { _ = try brightness.snapshot() }
            catch { lastError = error.localizedDescription; return }
        }
        agentsEnabled = on
        preferences.set(on, forKey: "agentsEnabled")
        displayPaused = false
        previousLid = nil
        lastError = nil
        tick()
    }

    private func tick() {
        guard started else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let health = GuardianManager.health(store: runtime)
        if guardianReady != health.ready { guardianReady = health.ready }
        let needsHelper = !MacState.helperReady
        if helperNeeded != needsHelper { helperNeeded = needsHelper }
        if health.ready {
            guardianRetryDelay = 15
            if let installError = guardianInstallError, lastError == installError { lastError = nil }
            guardianInstallError = nil
        }
        if pendingAutostart && health.ready && !repairingGuardian && !installingHelper {
            if FileManager.default.fileExists(atPath: runtime.sessionURL.path)
                || FileManager.default.fileExists(atPath: runtime.brightnessURL.path) {
                status = L10n.text("status.recovering")
            } else {
                pendingAutostart = false
                setActive(true)
            }
        }
        guard let lease else {
            if let requested = stopRequestedAt {
                if !MacState.sleepDisabled {
                    stopRequestedAt = nil
                    status = L10n.text("status.normal")
                } else if now - requested > 15 {
                    lastError = L10n.text("error.sleepUnconfirmed")
                    status = L10n.text("status.restoreFailed")
                }
            }
            let notice = try? runtime.read(RecoveryNotice.self, at: runtime.noticeURL)
            if recoveryNotice != notice { recoveryNotice = notice }
            if !health.responsive && !repairingGuardian && !installingHelper && now >= nextGuardianRetry {
                repairGuardian()
            }
            return
        }
        do {
            guard let current = try runtime.read(SessionLease.self, at: runtime.sessionURL), current.id == lease.id else {
                let notice = try? runtime.read(RecoveryNotice.self, at: runtime.noticeURL)
                abandonRecoveredSession(notice: notice ?? RecoveryNotice(date: Date(), reason: "error.sessionRecovered"))
                return
            }
            if let reason = MacState.safety.stopReason { stop(reason: reason); return }
            guard MacState.helperReady else {
                helperNeeded = true
                stop(reason: InsoniaFailure("error.helperUnavailable"))
                return
            }
            guard health.ready else {
                runtime.log("guardian_unavailable state=\(health.state.rawValue) age=\(health.age.map(String.init(describing:)) ?? "unknown")")
                stop(reason: health.failure ?? InsoniaFailure("error.guardianUnavailable"))
                return
            }
            if applying {
                if MacState.helperConfirmed(sessionID: lease.id) {
                    applying = false; active = true; activeSince = Date()
                    runtime.log("system_sleep_disabled_confirmed")
                } else if now - applyingSince > 15 {
                    stop(reason: InsoniaFailure("error.helperUnconfirmed"))
                    return
                }
            } else if !MacState.sleepDisabled {
                stop(reason: InsoniaFailure("error.sleepResumed"))
                return
            }
            guard let lid = MacState.lidClosed else {
                stop(reason: InsoniaFailure("error.lidLost"))
                return
            }
            if active {
                try updateDisplay(id: lease.id, lidClosed: lid)
                if previousLid != lid { runtime.log("lid_\(lid ? "closed" : "open") mode=\(agentsEnabled ? "agents" : "background")") }
                previousLid = lid
            }
            if now - lastRenewal >= 2 {
                try coordinator.renew(id: lease.id, mode: agentsEnabled ? .agents : .background, uptime: now)
                lastRenewal = now
            }
        } catch { stop(reason: InsoniaFailure.wrapping(error)) }
    }

    private func updateDisplay(id: String, lidClosed: Bool) throws {
        if !agentsEnabled {
            try coordinator.restore(id: id)
            displayActivity.release()
            if lidClosed && previousLid != true {
                guard try LocalProcess.run("/usr/bin/pmset", ["displaysleepnow"]) == 0 else {
                    throw InsoniaFailure("error.displaySleep")
                }
                runtime.log("display_sleep_requested")
            }
            status = L10n.text("status.background")
            return
        }
        if screenLocked || !MacState.sessionAvailable || displayPaused {
            displayActivity.release()
            try coordinator.restore(id: id)
            status = L10n.text("status.paused")
            return
        }
        guard DisplayBrightness.usableDisplay else {
            displayActivity.release()
            try coordinator.restore(id: id)
            status = L10n.text("status.displayUnavailable")
            runtime.log("display_unavailable")
            return
        }
        try displayActivity.maintain(lidClosed: lidClosed)
        if lidClosed {
            try coordinator.dim(id: id)
            status = L10n.text("status.dimmed")
        } else {
            try coordinator.restore(id: id)
            status = L10n.text("status.agentsReady")
        }
    }

    private func stop(reason: InsoniaFailure? = nil) {
        pendingAutostart = false
        var stopFailure: String?
        if let lease {
            do { try coordinator.end(id: lease.id, reason: reason) }
            catch { stopFailure = InsoniaFailure.wrapping(error).message }
            stopRequestedAt = ProcessInfo.processInfo.systemUptime
        }
        self.lease = nil
        displayActivity.release()
        sessionActivity.stop()
        active = false; applying = false; activeSince = nil; previousLid = nil
        status = MacState.sleepDisabled && stopRequestedAt != nil ? L10n.text("status.restoring") : L10n.text("status.normal")
        if let stopFailure { lastError = stopFailure }
        else { lastError = nil }
        if let reason {
            recoveryNotice = (try? runtime.read(RecoveryNotice.self, at: runtime.noticeURL))
                ?? RecoveryNotice(date: Date(), reason: reason)
        }
    }

    private func abandonRecoveredSession(notice: RecoveryNotice) {
        lease = nil
        displayActivity.release()
        sessionActivity.stop()
        active = false; applying = false; activeSince = nil
        lastError = nil
        recoveryNotice = notice
        status = L10n.text("status.stopped")
        stopRequestedAt = ProcessInfo.processInfo.systemUptime
    }

    func acknowledgeRecovery() {
        guard let notice = recoveryNotice else { return }
        do {
            try runtime.acknowledge(notice)
            recoveryNotice = try runtime.read(RecoveryNotice.self, at: runtime.noticeURL)
        } catch { lastError = InsoniaFailure.wrapping(error).message }
    }

    func repairGuardian() {
        guard lease == nil, !repairingGuardian, !installingHelper else { return }
        guard installedInApplications else { lastError = L10n.text("error.installLocation"); return }
        let restart = !GuardianManager.health(store: runtime).responsive
        repairingGuardian = true
        nextGuardianRetry = ProcessInfo.processInfo.systemUptime + guardianRetryDelay
        guardianRetryDelay = min(60, guardianRetryDelay * 2)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let failure: InsoniaFailure?
            do { try GuardianManager.install(restartUnresponsive: restart); failure = nil }
            catch { failure = InsoniaFailure.wrapping(error) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.repairingGuardian = false
                if let failure {
                    self.guardianInstallError = failure.message
                    self.lastError = failure.message
                }
            }
        }
    }

    func openHelp() {
        var components = URLComponents(url: L10n.resources.appendingPathComponent("Help/index.html"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "lang", value: L10n.language)]
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }

    func shutdown() {
        guard started else { return }
        stop(); timer?.invalidate(); timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll(); started = false
    }

    private func observeSession() {
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping () -> Void) {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
            observers.append((center, observer))
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.screenLocked = true; self?.runtime.log("session_locked"); self?.tick()
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.screenLocked = false; self?.displayPaused = false
            self?.runtime.log("session_unlocked"); self?.tick()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.displayPaused = true; self?.tick()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.displayPaused = false; self?.tick()
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.screenLocked = true; self?.tick()
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.screenLocked = !MacState.sessionAvailable; self?.displayPaused = false; self?.tick()
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.stop(reason: InsoniaFailure("error.macSlept"))
        }
    }

    func setActivateOnLaunch(_ on: Bool) {
        activateOnLaunch = on; preferences.set(on, forKey: "activateOnLaunch")
    }

    private static var agentPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    func setOpenAtLogin(_ on: Bool) {
        do { try configureOpenAtLogin(on) }
        catch { lastError = L10n.text("error.login", InsoniaFailure.wrapping(error).message) }
    }

    private func configureOpenAtLogin(_ on: Bool) throws {
        let target = "gui/\(getuid())/\(agentLabel)"
        if on {
            guard let executable = Bundle.main.executablePath else { return }
            let job: [String: Any] = ["Label": agentLabel, "ProgramArguments": [executable],
                "RunAtLoad": true, "KeepAlive": false, "ProcessType": "Interactive"]
            let url = URL(fileURLWithPath: Self.agentPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            guard try LocalProcess.run("/bin/launchctl", ["enable", target]) == 0 else {
                throw InsoniaFailure("launchctl enable: " + agentLabel)
            }
        } else {
            guard try LocalProcess.run("/bin/launchctl", ["disable", target]) == 0 else {
                throw InsoniaFailure("launchctl disable: " + agentLabel)
            }
            if FileManager.default.fileExists(atPath: Self.agentPath) {
                try FileManager.default.removeItem(atPath: Self.agentPath)
            }
        }
        openAtLogin = FileManager.default.fileExists(atPath: Self.agentPath)
    }

    func installHelper() {
        authorizeHelper(uninstall: false)
    }

    func removeProtection() {
        guard !installingHelper, !repairingGuardian else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("ui.removeTitle")
        alert.informativeText = L10n.text("ui.removeDescription")
        alert.addButton(withTitle: L10n.text("ui.cancel"))
        alert.addButton(withTitle: L10n.text("ui.remove"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        authorizeHelper(uninstall: true)
    }

    private func authorizeHelper(uninstall: Bool) {
        guard !installingHelper, !repairingGuardian else { return }
        guard installedInApplications else { lastError = L10n.text("error.installLocation"); return }
        stop()
        if FileManager.default.fileExists(atPath: runtime.brightnessURL.path) {
            lastError = L10n.text("error.restoreBrightness")
            return
        }
        let script = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/helper-install/install-helper.sh").path
        func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "/bin/bash \(shellQuote(script)) --user \(shellQuote(NSUserName()))" + (uninstall ? " --uninstall" : "")
        let appleString = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(appleString)\" with administrator privileges"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        installingHelper = true; lastError = nil; helperProcess = process
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                self.installingHelper = false; self.helperProcess = nil
                self.helperNeeded = !MacState.helperReady
                if uninstall && process.terminationStatus == 0 && !MacState.sleepDisabled {
                    do {
                        try GuardianManager.uninstall()
                        try self.configureOpenAtLogin(false)
                        self.setActivateOnLaunch(false)
                        self.status = L10n.text("ui.removed")
                        NSApp.terminate(nil)
                    } catch { self.lastError = InsoniaFailure.wrapping(error).message }
                } else {
                    self.lastError = process.terminationStatus == 0 && !self.helperNeeded
                        ? nil : L10n.text("error.authorization")
                }
            }
        }
        do { try process.run() }
        catch { installingHelper = false; helperProcess = nil; lastError = InsoniaFailure.wrapping(error).message }
    }
}
