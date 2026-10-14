import Foundation
import Darwin

final class FakeBrightness: BrightnessControlling {
    var value: Float = 0.6
    var snapshotCount = 0
    var failWrite = false
    var beforeWrite: ((Float) throws -> Void)?
    func snapshot() throws -> BrightnessSnapshot {
        snapshotCount += 1
        return BrightnessSnapshot(displayUUID: "built-in-test", brightness: value)
    }
    func current(for displayUUID: String) throws -> Float { value }
    func set(_ value: Float, for displayUUID: String) throws {
        try beforeWrite?(value)
        if failWrite { throw InsoniaFailure("simulated display failure") }
        self.value = value
    }
}

@main struct RuntimeTests {
    static var count = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw InsoniaFailure("FAIL: \(message)") }
        count += 1
    }
    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch { count += 1; return }
        throw InsoniaFailure("FAIL: \(message)")
    }
    static func main() {
        do { try run() }
        catch { print(error.localizedDescription); exit(1) }
    }
    static func run() throws {
        var starts = 0
        var stops = 0
        var activity: SessionActivity? = SessionActivity(begin: { starts += 1; return NSObject() }, end: { _ in stops += 1 })
        activity?.start(); activity?.start()
        try check(starts == 1, "one App Nap exemption per session")
        activity?.stop(); activity?.stop()
        try check(stops == 1, "App Nap exemption ends once on stop")
        activity?.start()
        try check(starts == 2, "new session takes a new exemption")
        activity = nil
        try check(stops == 2, "App Nap exemption ends on deallocation")
        try check(LeasePolicy.isFresh(heartbeat: 100, now: 130), "heartbeat boundary")
        try check(!LeasePolicy.isFresh(heartbeat: 100, now: 130.01), "expired heartbeat")
        try check(!LeasePolicy.isFresh(heartbeat: 100, now: 99), "reboot/future heartbeat")
        try check(!LeasePolicy.isFresh(heartbeat: .nan, now: 100), "invalid heartbeat")
        try check(SafetyReading(onBattery: true, batteryPercent: 15, thermalState: .nominal).stopReason != nil, "battery cutoff")
        try check(SafetyReading(onBattery: true, batteryPercent: 16, thermalState: .nominal).stopReason == nil, "battery above cutoff")
        try check(SafetyReading(onBattery: false, batteryPercent: 4, thermalState: .nominal).stopReason == nil, "charging allowed")
        try check(SafetyReading(onBattery: true, batteryPercent: nil, thermalState: .nominal).stopReason != nil, "unknown battery fails closed")
        try check(SafetyReading(onBattery: false, batteryPercent: 99, thermalState: .serious).stopReason != nil, "thermal cutoff on AC")
        try check(SafetyReading(onBattery: true, batteryPercent: 99, thermalState: .critical).stopReason != nil, "critical thermal cutoff")
        for (preferences, expected) in [(["pt-BR"], "pt"), (["pt-PT"], "pt"), (["es-MX"], "es"),
            (["fr-CA"], "fr"), (["de-AT"], "de"), (["it-CH"], "it"), (["ja", "fr"], "fr"),
            (["en-GB", "pt"], "en"), (["zh-Hant"], "en"), ([], "en"), (["PT_br"], "pt")] {
            try check(LocalizationCatalog.language(for: preferences) == expected, "system language resolution \(preferences)")
        }
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let english = LocalizationCatalog(resources: resources, preferences: ["en"])
        let french = LocalizationCatalog(resources: resources, preferences: ["fr"])
        try check(english.text("ui.keepAwake") == "Keep awake", "English catalog loading")
        try check(french.text("ui.keepAwake") != english.text("ui.keepAwake"), "French catalog loading")
        try check(english.text("error.login", arguments: ["detail {0}"]) == "Could not change login startup: detail {0}", "arguments are substituted only once")
        let legacyData = Data(#"{"date":813597236.774865,"message":"O monitor de recuperação não está respondendo. O Insônia foi desativado."}"#.utf8)
        let legacyNotice = try JSONDecoder().decode(RecoveryNotice.self, from: legacyData)
        try check(legacyNotice.reason.key == "error.guardianUnavailable", "legacy Portuguese recovery key migrated")
        try check(english.text(legacyNotice.reason.key).contains("Insonia"), "legacy notice follows new display language")
        let batteryNotice = RecoveryNotice(date: Date(), reason: InsoniaFailure("safety.battery", "12"))
        let decodedNotice = try JSONDecoder().decode(RecoveryNotice.self, from: JSONEncoder().encode(batteryNotice))
        try check(decodedNotice == batteryNotice, "structured notice retains key and arguments")
        try check(french.text(decodedNotice.reason.key, arguments: decodedNotice.reason.arguments).contains("12"), "persisted notice rendered in another language")
        try check(InsoniaFailure.wrapping(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))).key == "error.storage", "disk-full diagnosis")

        let pulse = GuardianPulse(version: RuntimeStore.guardianVersion, pid: 123, uptime: 100)
        try check(GuardianHealth.evaluate(pulse, now: 101, processAlive: { _ in true }).ready, "fresh guardian ready")
        try check(GuardianHealth.evaluate(pulse, now: 108, processAlive: { _ in true }).state == .stale, "stale guardian blocked")
        try check(GuardianHealth.evaluate(pulse, now: 99, processAlive: { _ in true }).state == .future, "future guardian blocked")
        try check(GuardianHealth.evaluate(pulse, now: 101, processAlive: { _ in false }).state == .processExited, "dead guardian blocked")
        try check(GuardianHealth.evaluate(nil, now: 101, processAlive: { _ in true }).state == .missing, "missing guardian blocked")
        try check(GuardianHealth.evaluate(GuardianPulse(version: 2, pid: 123, uptime: 100), now: 101, processAlive: { _ in true }).state == .incompatible, "old guardian blocked")
        let idle = UpdateReadiness(sleepDisabled: false, normalSleepConfirmed: true)
        try check(idle.canInstall, "normal sleep and clear journals allow installation")
        try check(!UpdateReadiness(sleepDisabled: false, normalSleepConfirmed: false).canInstall,
            "an old OS zero without a fresh root receipt cannot permit installation")
        let oldSleepReceipt = HelperReceipt("3 100 0 -")!
        let freshSleepReceipt = HelperReceipt("3 101 0 -")!
        try check(!oldSleepReceipt.confirmsNormalSleep(after: 100.25, now: 101), "pre-stop zero receipt is rejected")
        try check(freshSleepReceipt.confirmsNormalSleep(after: 100.25, now: 102), "later root receipt confirms normal sleep")
        try check(!freshSleepReceipt.confirmsNormalSleep(after: 100.25, now: 127), "expired normal-sleep receipt is rejected")
        try check(!freshSleepReceipt.isRecent(now: 100), "future helper receipt is rejected")
        try check(HelperReceipt("3 nan 0 -") == nil, "non-finite helper receipt is rejected")
        try check(HelperReceipt("3 100 1 -") == nil, "active helper receipt must identify its session")
        for state in [UpdateReadiness(sessionActive: true, sleepDisabled: false, normalSleepConfirmed: true),
                      UpdateReadiness(protectionBusy: true, sleepDisabled: false, normalSleepConfirmed: true),
                      UpdateReadiness(stopPending: true, sleepDisabled: false, normalSleepConfirmed: true),
                      UpdateReadiness(persistedSession: true, sleepDisabled: false, normalSleepConfirmed: true),
                      UpdateReadiness(brightnessPending: true, sleepDisabled: false, normalSleepConfirmed: true),
                      UpdateReadiness(guardianRecovering: true, sleepDisabled: false, normalSleepConfirmed: true),
                      UpdateReadiness(sleepDisabled: true), UpdateReadiness(sleepDisabled: nil)] {
            try check(!state.canInstall, "every busy, recovery or unreadable condition defers installation")
        }
        for preference in [false, true] {
            for resume in [false, true] {
                try check(!LaunchPolicy.shouldActivate(preference: preference, resumeRequested: resume,
                    updateRelaunch: true, recoveryNoticePresent: false), "update relaunch never starts an awake session")
                try check(!LaunchPolicy.shouldActivate(preference: preference, resumeRequested: resume,
                    updateRelaunch: false, recoveryNoticePresent: true), "protective incident requires manual reactivation")
            }
        }
        try check(LaunchPolicy.shouldActivate(preference: true, resumeRequested: false,
            updateRelaunch: false, recoveryNoticePresent: false), "ordinary clean login respects autostart preference")
        let installGate = UpdateInstallGate()
        var installations = 0
        var preparations = 0
        installGate.enqueue { installations += 1 }
        try installGate.advance(readiness: UpdateReadiness(sessionActive: true, sleepDisabled: true)) { preparations += 1 }
        try check(installations == 0 && preparations == 0 && installGate.isWaiting, "active work is never interrupted by an update")
        try rejects("failed preparation cannot hand off installation") {
            try installGate.advance(readiness: idle) { throw InsoniaFailure("simulated preparation failure") }
        }
        try check(installations == 0 && installGate.isWaiting, "failed preparation retains the continuation for retry")
        try installGate.advance(readiness: idle) { preparations += 1 }
        try installGate.advance(readiness: idle) { preparations += 1 }
        try check(installations == 1 && preparations == 1, "installation continuation runs exactly once")
        installGate.enqueue { installations += 10 }
        installGate.cancel()
        try installGate.advance(readiness: idle) { preparations += 1 }
        try check(installations == 1, "cancelled update never installs")
        installGate.enqueue {
            installations += 1
            installGate.enqueue { installations += 1 }
        }
        try installGate.advance(readiness: idle) { }
        try check(installations == 2 && installGate.isWaiting, "reentrant callback preserves next installation stage")
        try installGate.advance(readiness: idle) { }
        try check(installations == 3 && !installGate.isWaiting, "second stage completes exactly once")
        var retryTime: TimeInterval = 100
        var scheduledRetry: (() -> Void)?
        var cancelledRetries = 0
        var retries = 0
        let retryScheduler = UpdateRetryScheduler(clock: { retryTime }, schedule: { delay, action in
            scheduledRetry = action
            return { cancelledRetries += 1 }
        })
        retryScheduler.retry(after: 10) { retries += 1 }
        retryTime = 102
        try check(!retryScheduler.isReady, "readiness becoming healthy within backoff does not retry early")
        retryTime = 110
        scheduledRetry?()
        try check(retries == 1 && retryScheduler.isReady, "stable readiness still retries at backoff expiry")
        scheduledRetry?()
        try check(retries == 1, "retry timer callback cannot run twice")
        retryScheduler.retry(after: 10) { retries += 1 }
        retryScheduler.cancel()
        scheduledRetry?()
        try check(retries == 1 && cancelledRetries == 1, "cancelled update cannot resurrect a queued retry")

        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/test-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }
        let store = RuntimeStore(base: output)
        let fake = FakeBrightness()
        let coordinator = SessionCoordinator(store: store, brightness: fake)
        let safe = SafetyReading(onBattery: false, batteryPercent: 80, thermalState: .nominal)
        try coordinator.guardianWillTerminate()
        try check(!FileManager.default.fileExists(atPath: store.noticeURL.path), "inactive guardian shutdown creates no false warning")
        try check(!FileManager.default.fileExists(atPath: store.desiredURL.path), "inactive guardian shutdown does not mutate system request")
        var synchronizedFiles: [String] = []
        let receiptStore = RuntimeStore(base: output.appendingPathComponent("receipt-io"), synchronize: { url in
            synchronizedFiles.append(url.lastPathComponent)
        })
        let receiptBrightness = FakeBrightness()
        let receiptCoordinator = SessionCoordinator(store: receiptStore, brightness: receiptBrightness)
        let receiptLease = try receiptCoordinator.begin(mode: .agents, pid: 123, uptime: 100)
        try check(synchronizedFiles == ["session.json"], "initial session intent is durable")
        synchronizedFiles.removeAll()
        try receiptCoordinator.renew(id: receiptLease.id, mode: .agents, uptime: 101)
        try GuardianCycle(coordinator: receiptCoordinator).tick(safety: safe, processAlive: { _ in true }, uptime: { 102 }, pid: 123)
        try check(synchronizedFiles.isEmpty, "periodic lease and guardian receipts do not wait for disk flushes")
        receiptBrightness.beforeWrite = { value in
            if value < 0.1 {
                try check(synchronizedFiles.contains("brightness-restore.json"), "brightness journal is synchronized before changing hardware")
            }
        }
        try receiptCoordinator.dim(id: receiptLease.id)
        try receiptCoordinator.end(id: receiptLease.id, reason: "safety.thermal")
        try check(synchronizedFiles.contains("autostart-blocked.json") && synchronizedFiles.contains("notice.json"),
            "protective decisions remain durable")
        try store.markUpdateRelaunch()
        try check(try store.consumeUpdateRelaunch(), "durable update relaunch marker is consumed")
        try check(try !store.consumeUpdateRelaunch(), "update marker suppresses only one launch")
        try Data("interrupted marker".utf8).write(to: store.updateRelaunchURL)
        try check(try store.consumeUpdateRelaunch(), "corrupt update marker still fails closed on autostart")
        try store.notePotentialUpdate(fromBuild: "4")
        try check(try !store.consumeUpdateRelaunch(currentBuild: "4"), "an offered but uninstalled update preserves ordinary login preference")
        try check(FileManager.default.fileExists(atPath: store.updateRelaunchURL.path), "offered update evidence survives until actual version changes")
        try check(try store.consumeUpdateRelaunch(currentBuild: "5"), "actual replacement suppresses automatic activation")
        try check(!FileManager.default.fileExists(atPath: store.updateRelaunchURL.path), "applied update evidence is consumed once")
        try store.markUpdateRelaunch()
        try store.notePotentialUpdate(fromBuild: "4")
        try check(try store.consumeUpdateRelaunch(currentBuild: "4"), "later offer cannot weaken committed relaunch intent")
        try Data("interrupted marker".utf8).write(to: store.updateRelaunchURL)
        try store.notePotentialUpdate(fromBuild: "4")
        try check(try store.consumeUpdateRelaunch(currentBuild: "4"), "later offer cannot replace unreadable safety evidence")
        let first = try coordinator.begin(mode: .agents, pid: 100, uptime: 100)
        try rejects("active persisted session cannot prepare update marker") { try store.markUpdateRelaunch() }
        var clockObservedWhileLocked = false
        func recoveryClock() -> TimeInterval {
            let fd = open(store.runtime.appendingPathComponent("session.lock").path, O_RDWR)
            guard fd >= 0 else { return 101 }
            defer { close(fd) }
            if flock(fd, LOCK_EX | LOCK_NB) != 0 { clockObservedWhileLocked = true }
            else { flock(fd, LOCK_UN) }
            return 101
        }
        try coordinator.recoverIfNeeded(now: recoveryClock(), processAlive: { _ in true }, safety: safe)
        try check(clockObservedWhileLocked, "recovery samples clock inside lease lock, after a queued renewal")
        try check(try String(contentsOf: store.desiredURL, encoding: .utf8) == "1", "start requests sleep inhibition")
        try check(FileManager.default.fileExists(atPath: store.heartbeatURL.path), "start creates heartbeat")
        try rejects("overlapping session rejected") { _ = try coordinator.begin(mode: .agents) }
        fake.beforeWrite = { value in
            if value < 0.1 {
                try check(try store.read(BrightnessSnapshot.self, at: store.brightnessURL)?.brightness == 0.6, "journal before mutation")
            }
        }
        try coordinator.dim(id: first.id)
        try coordinator.dim(id: first.id)
        try check(abs(fake.value - 0.01) < 0.001, "hardware dim")
        try check(fake.snapshotCount == 1, "repeated dim preserves original brightness")
        try coordinator.recoverIfNeeded(now: 125, processAlive: { _ in true }, safety: safe)
        try check(try store.read(SessionLease.self, at: store.sessionURL)?.id == first.id, "healthy lease retained")
        fake.beforeWrite = { value in
            if value == 0.6 {
                try check(try String(contentsOf: store.desiredURL, encoding: .utf8) == "1", "restore happens before sleep enabled")
            }
        }
        try coordinator.end(id: first.id)
        try check(fake.value == 0.6, "stop restores brightness")
        try check(!FileManager.default.fileExists(atPath: store.brightnessURL.path), "verified restore removes journal")
        try check(try String(contentsOf: store.desiredURL, encoding: .utf8) == "0", "stop requests normal sleep")
        try check(!FileManager.default.fileExists(atPath: store.heartbeatURL.path), "stop removes heartbeat")
        fake.beforeWrite = nil

        let second = try coordinator.begin(mode: .agents, pid: 101, uptime: 200)
        try rejects("old session cannot end new session") { try coordinator.end(id: first.id) }
        try rejects("old session cannot renew new session") { try coordinator.renew(id: first.id, mode: .agents) }
        try rejects("old session cannot dim new session") { try coordinator.dim(id: first.id) }
        try check(try store.read(SessionLease.self, at: store.sessionURL)?.id == second.id, "new ownership preserved")
        try coordinator.dim(id: second.id)
        fake.failWrite = true
        try rejects("restore failure surfaces") { try coordinator.end(id: second.id, reason: "test recovery") }
        try check(FileManager.default.fileExists(atPath: store.brightnessURL.path), "failed restore keeps journal")
        try check(try String(contentsOf: store.desiredURL, encoding: .utf8) == "0", "failure still re-enables normal sleep")
        try check(try store.read(SessionLease.self, at: store.sessionURL) == nil, "failure invalidates session")
        try rejects("pending brightness recovery prevents update preparation after session ended") { try store.markUpdateRelaunch() }
        fake.failWrite = false
        try coordinator.recoverIfNeeded(now: 300, processAlive: { _ in true }, safety: safe)
        try check(fake.value == 0.6, "orphan journal retry restores brightness")
        try check(!FileManager.default.fileExists(atPath: store.brightnessURL.path), "retry clears journal")

        // A display failure is not a dead guardian; it still publishes a degraded pulse.
        try store.write(BrightnessSnapshot(displayUUID: "built-in-test", brightness: 0.6), to: store.brightnessURL)
        fake.failWrite = true
        let cycle = GuardianCycle(coordinator: coordinator)
        try cycle.tick(safety: safe, processAlive: { _ in true }, uptime: { 310 }, pid: 123)
        let degraded = try store.read(GuardianPulse.self, at: store.guardianURL)
        let degradedHealth = GuardianHealth.evaluate(degraded, now: 311, processAlive: { _ in true })
        try check(degradedHealth.responsive && !degradedHealth.ready, "failed restore publishes responsive degraded heartbeat")
        try check(FileManager.default.fileExists(atPath: store.brightnessURL.path), "degraded recovery preserves brightness journal")
        fake.failWrite = false
        try cycle.tick(safety: safe, processAlive: { _ in true }, uptime: { 312 }, pid: 123)
        try check(GuardianHealth.evaluate(try store.read(GuardianPulse.self, at: store.guardianURL), now: 313, processAlive: { _ in true }).ready, "recovery becomes ready on successful retry")

        try store.write(legacyNotice, to: store.noticeURL)
        try store.acknowledge(legacyNotice)
        try check(try store.read(RecoveryNotice.self, at: store.noticeURL) == nil, "acknowledged notice stays removed")
        try check(store.protectiveStopPending, "dismissing an incident does not authorize autostart")
        try rejects("a pending autostart evaluated before recovery cannot bypass a newly written latch") {
            _ = try coordinator.begin(mode: .agents, allowAfterProtectiveStop: false)
        }
        try check(store.protectiveStopPending, "rejected autostart preserves protective state")
        try store.write(batteryNotice, to: store.noticeURL)
        try store.acknowledge(legacyNotice)
        try check(try store.read(RecoveryNotice.self, at: store.noticeURL) == batteryNotice, "old acknowledgement cannot erase newer incident")

        let third = try coordinator.begin(mode: .agents, pid: 102, uptime: 400)
        try check(!store.protectiveStopPending, "a new requested session clears the protective autostart latch")
        try coordinator.dim(id: third.id)
        try coordinator.recoverIfNeeded(now: 431, processAlive: { _ in true }, safety: safe)
        try check(try store.read(SessionLease.self, at: store.sessionURL) == nil, "hung app recovered")
        try check(fake.value == 0.6, "hung app restores brightness")
        _ = try coordinator.begin(mode: .agents, pid: 103, uptime: 500)
        try coordinator.recoverIfNeeded(now: 501, processAlive: { _ in false }, safety: safe)
        try check(try store.read(SessionLease.self, at: store.sessionURL) == nil, "dead app recovered immediately")
        _ = try coordinator.begin(mode: .background, pid: 104, uptime: 600)
        try coordinator.recoverIfNeeded(now: 601, processAlive: { _ in true },
            safety: SafetyReading(onBattery: true, batteryPercent: 10, thermalState: .nominal))
        try check(try store.read(SessionLease.self, at: store.sessionURL) == nil, "guardian enforces battery limit")
        _ = try coordinator.begin(mode: .agents, pid: 105, uptime: 700)
        try coordinator.recoverIfNeeded(now: 701, processAlive: { _ in true },
            safety: SafetyReading(onBattery: false, batteryPercent: 100, thermalState: .serious))
        try check(try store.read(SessionLease.self, at: store.sessionURL) == nil, "guardian enforces thermal limit")
        _ = try coordinator.begin(mode: .agents, pid: 106, uptime: 800)
        try Data("invalid".utf8).write(to: store.sessionURL)
        try coordinator.recoverIfNeeded(now: 801, processAlive: { _ in true }, safety: safe)
        try check(try String(contentsOf: store.desiredURL, encoding: .utf8) == "0", "corrupt lease fails closed")

        var diskFull = false
        let diskStore = RuntimeStore(base: output.appendingPathComponent("disk-full"), writeData: { data, url in
            if diskFull { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError) }
            try data.write(to: url, options: .atomic)
        })
        let diskCoordinator = SessionCoordinator(store: diskStore, brightness: FakeBrightness())
        let diskCycle = GuardianCycle(coordinator: diskCoordinator)
        try diskCycle.tick(safety: safe, processAlive: { _ in true }, uptime: { 100 }, pid: 123)
        diskFull = true
        try rejects("update admission fails before extraction when its durable intent cannot be saved") {
            try diskStore.notePotentialUpdate(fromBuild: "4")
        }
        try rejects("disk-full heartbeat cannot pretend to succeed") {
            try diskCycle.tick(safety: safe, processAlive: { _ in true }, uptime: { 109 }, pid: 123)
        }
        try check(GuardianHealth.evaluate(try diskStore.read(GuardianPulse.self, at: diskStore.guardianURL), now: 109, processAlive: { _ in true }).state == .stale, "unwritable heartbeat expires safely")
        try rejects("disk-full session cannot activate") { _ = try diskCoordinator.begin(mode: .agents) }
        try check(!FileManager.default.fileExists(atPath: diskStore.desiredURL.path), "failed activation leaves no awake request")
        diskFull = false
        try diskCycle.tick(safety: safe, processAlive: { _ in true }, uptime: { 110 }, pid: 123)
        try check(GuardianHealth.evaluate(try diskStore.read(GuardianPulse.self, at: diskStore.guardianURL), now: 111, processAlive: { _ in true }).ready, "monitor recovers when disk is writable again")
        var blockWriteFails = false
        let blockedStore = RuntimeStore(base: output.appendingPathComponent("protective-write"), writeData: { data, url in
            if blockWriteFails && url.lastPathComponent == "autostart-blocked.json" {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
            }
            try data.write(to: url, options: .atomic)
        })
        let blockedCoordinator = SessionCoordinator(store: blockedStore, brightness: FakeBrightness())
        let blockedLease = try blockedCoordinator.begin(mode: .agents, pid: 100, uptime: 100)
        blockWriteFails = true
        try rejects("disk-full protective latch preserves evidence for recovery retry") {
            try blockedCoordinator.end(id: blockedLease.id, reason: "safety.thermal")
        }
        try check(try blockedStore.read(SessionLease.self, at: blockedStore.sessionURL)?.id == blockedLease.id,
            "lease is retained until protective stop is durable")
        try check(!FileManager.default.fileExists(atPath: blockedStore.heartbeatURL.path), "failed protective persistence still invalidates root heartbeat")
        try check(try String(contentsOf: blockedStore.desiredURL, encoding: .utf8) == "0", "failed protective persistence still requests normal sleep")
        try rejects("deferred autostart cannot pass the retained lease") {
            _ = try blockedCoordinator.begin(mode: .agents, allowAfterProtectiveStop: false)
        }
        blockWriteFails = false
        try blockedCoordinator.recoverIfNeeded(now: 132, processAlive: { _ in true }, safety: safe)
        try check(blockedStore.protectiveStopPending, "recovery retry persists the protection latch before clearing lease")
        try check(try blockedStore.read(SessionLease.self, at: blockedStore.sessionURL) == nil, "recovery retry completes after storage recovers")
        try rejects("newly completed recovery still forbids pending autostart") {
            _ = try blockedCoordinator.begin(mode: .agents, allowAfterProtectiveStop: false)
        }
        print("PASS: \(count) runtime and safety assertions")
    }
}
