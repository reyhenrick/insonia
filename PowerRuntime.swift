import Foundation
import Darwin

struct BrightnessSnapshot: Codable, Equatable {
    let displayUUID: String
    let brightness: Float
}

protocol BrightnessControlling {
    func snapshot() throws -> BrightnessSnapshot
    func set(_ value: Float, for displayUUID: String) throws
    func current(for displayUUID: String) throws -> Float
}

struct SessionLease: Codable {
    let id: String
    let pid: Int32
    var mode: LidMode
    var heartbeatUptime: TimeInterval
    var heartbeatDate: Date
}

struct RecoveryNotice: Codable, Equatable {
    let date: Date
    let reason: InsoniaFailure
    var message: String { reason.message }

    init(date: Date, reason: InsoniaFailure) { self.date = date; self.reason = reason }
    private enum CodingKeys: String, CodingKey { case date, reason, message }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        if let structured = try container.decodeIfPresent(InsoniaFailure.self, forKey: .reason) {
            reason = structured
        } else {
            reason = L10n.catalog.legacyMessage(try container.decode(String.self, forKey: .message))
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(reason, forKey: .reason)
    }
}

struct GuardianPulse: Codable {
    let version: Int
    let pid: Int32
    let uptime: TimeInterval
    var recoveryFailure: InsoniaFailure? = nil
}

struct UpdateRelaunchIntent: Codable {
    let createdAt: TimeInterval
    let offeredFromBuild: String?
}

enum GuardianHealthState: String {
    case ready, recovering, missing, unreadable, incompatible, future, stale, processExited
}

struct GuardianHealth {
    let state: GuardianHealthState
    let age: TimeInterval?
    let failure: InsoniaFailure?
    var ready: Bool { state == .ready }
    var responsive: Bool { state == .ready || state == .recovering }

    static func evaluate(_ pulse: GuardianPulse?, now: TimeInterval,
                         processAlive: (Int32) -> Bool) -> GuardianHealth {
        guard let pulse else { return GuardianHealth(state: .missing, age: nil, failure: nil) }
        let age = now - pulse.uptime
        let state: GuardianHealthState
        if pulse.version != RuntimeStore.guardianVersion { state = .incompatible }
        else if !pulse.uptime.isFinite || !now.isFinite || age < 0 { state = .future }
        else if age >= 8 { state = .stale }
        else if !processAlive(pulse.pid) { state = .processExited }
        else { state = pulse.recoveryFailure == nil ? .ready : .recovering }
        return GuardianHealth(state: state, age: age.isFinite ? age : nil, failure: pulse.recoveryFailure)
    }
}

/// Every app/guardian transition uses the same stable flock. Never unlink the lock.
final class RuntimeStore {
    static let helperVersion = 3
    static let guardianVersion = 3
    let base: URL
    let runtime: URL
    private let writeData: (Data, URL) throws -> Void
    private let synchronize: (URL) throws -> Void

    init(base: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Insonia"),
        writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
        synchronize: @escaping (URL) throws -> Void = { url in
            let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            defer { close(fd) }
            guard fsync(fd) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }) {
        self.base = base
        runtime = base.appendingPathComponent("runtime")
        self.writeData = writeData
        self.synchronize = synchronize
    }

    var desiredURL: URL { base.appendingPathComponent("desired-state") }
    var heartbeatURL: URL { runtime.appendingPathComponent("heartbeat") }
    var sessionURL: URL { runtime.appendingPathComponent("session.json") }
    var brightnessURL: URL { runtime.appendingPathComponent("brightness-restore.json") }
    var noticeURL: URL { runtime.appendingPathComponent("notice.json") }
    var guardianURL: URL { runtime.appendingPathComponent("guardian.json") }
    var updateRelaunchURL: URL { runtime.appendingPathComponent("update-relaunch.json") }
    var autostartBlockURL: URL { runtime.appendingPathComponent("autostart-blocked.json") }
    var protectiveStopPending: Bool {
        FileManager.default.fileExists(atPath: autostartBlockURL.path)
            || FileManager.default.fileExists(atPath: noticeURL.path)
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        for url in [base, runtime] {
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            if permissions?.intValue != 0o700 {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
        }
    }

    func locked<T>(_ body: () throws -> T) throws -> T {
        try prepare()
        let fd = open(runtime.appendingPathComponent("session.lock").path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw InsoniaFailure("error.sessionLockOpen") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw InsoniaFailure("error.sessionLock") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    func write<T: Encodable>(_ value: T, to url: URL, durable: Bool = true) throws {
        let data = try JSONEncoder().encode(value)
        try writeData(data, url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // Journals precede physical changes and must reach disk. Periodic
        // liveness receipts need atomic visibility, not a disk flush per tick.
        if durable { try synchronize(url) }
    }

    func remove(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func requestSleepDisabled(_ on: Bool) throws {
        try writeData(Data((on ? "1" : "0").utf8), desiredURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: desiredURL.path)
    }

    func heartbeat(sessionID: String) throws {
        try writeData(Data((sessionID + "\n").utf8), heartbeatURL)
    }

    /// An acknowledgement of an older incident cannot remove a newer one.
    func acknowledge(_ expected: RecoveryNotice) throws {
        try locked {
            if try read(RecoveryNotice.self, at: noticeURL) == expected {
                // Acknowledging the message is not a request to restart the session.
                // This also migrates notices written by versions before this latch.
                try write(["createdAt": expected.date.timeIntervalSince1970], to: autostartBlockURL)
                try remove(noticeURL)
            }
        }
    }

    func markUpdateRelaunch() throws {
        try locked {
            guard !FileManager.default.fileExists(atPath: sessionURL.path),
                  !FileManager.default.fileExists(atPath: brightnessURL.path) else {
                throw InsoniaFailure("error.updateRecovery")
            }
            try write(UpdateRelaunchIntent(createdAt: Date().timeIntervalSince1970, offeredFromBuild: nil), to: updateRelaunchURL)
        }
    }

    func notePotentialUpdate(fromBuild: String) throws {
        try locked {
            // An offered update must never weaken an existing committed (or
            // unreadable) relaunch intent left by an interrupted installation.
            if FileManager.default.fileExists(atPath: updateRelaunchURL.path) { return }
            try write(UpdateRelaunchIntent(createdAt: Date().timeIntervalSince1970,
                offeredFromBuild: fromBuild), to: updateRelaunchURL)
        }
    }

    /// An interrupted update also suppresses autostart once. Even a malformed
    /// marker must not turn a protective shutdown into an automatic activation.
    func consumeUpdateRelaunch(currentBuild: String? = nil) throws -> Bool {
        try locked {
            let present = FileManager.default.fileExists(atPath: updateRelaunchURL.path)
            if let currentBuild, let intent = try? read(UpdateRelaunchIntent.self, at: updateRelaunchURL),
               intent.offeredFromBuild == currentBuild {
                // Offering a release is not installing it. Keep the evidence
                // for a later actual replacement without changing ordinary login.
                return false
            }
            if present { try remove(updateRelaunchURL) }
            return present
        }
    }

    func log(_ event: String) {
        let url = runtime.appendingPathComponent("events.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(event)\n"
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 65_536 {
            let previous = runtime.appendingPathComponent("events.previous.log")
            try? remove(previous)
            try? FileManager.default.moveItem(at: url, to: previous)
        }
        let fd = open(url.path, O_CREAT | O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0o600)
        if fd >= 0 {
            line.withCString { pointer in _ = Darwin.write(fd, pointer, strlen(pointer)) }
            close(fd)
        }
    }
}

/// Shared by the app and the independent guardian. A stale owner can never dim,
/// restore, renew, or end a newer session.
final class SessionCoordinator {
    let store: RuntimeStore
    let brightness: BrightnessControlling
    static let minimumBrightness: Float = 0.01

    init(store: RuntimeStore, brightness: BrightnessControlling) {
        self.store = store
        self.brightness = brightness
    }

    func begin(mode: LidMode, pid: Int32 = getpid(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
               allowAfterProtectiveStop: Bool = true) throws -> SessionLease {
        try store.locked {
            guard allowAfterProtectiveStop || !store.protectiveStopPending else {
                throw InsoniaFailure("error.sessionRecovered")
            }
            guard try store.read(SessionLease.self, at: store.sessionURL) == nil else {
                throw InsoniaFailure("error.previousSession")
            }
            try restoreBrightnessLocked()
            let lease = SessionLease(id: UUID().uuidString, pid: pid, mode: mode,
                heartbeatUptime: uptime, heartbeatDate: Date())
            try store.write(lease, to: store.sessionURL)
            do {
                try store.heartbeat(sessionID: lease.id)
                try store.requestSleepDisabled(true)
            } catch {
                try? store.remove(store.heartbeatURL)
                try? store.requestSleepDisabled(false)
                try? store.remove(store.sessionURL)
                throw error
            }
            try? store.remove(store.noticeURL)
            try? store.remove(store.autostartBlockURL)
            store.log("session_started mode=\(mode.rawValue)")
            return lease
        }
    }

    func renew(id: String, mode: LidMode, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        try store.locked {
            var lease = try owned(id)
            lease.mode = mode
            lease.heartbeatUptime = uptime
            lease.heartbeatDate = Date()
            try store.write(lease, to: store.sessionURL, durable: false)
            try store.heartbeat(sessionID: lease.id)
        }
    }

    func dim(id: String) throws {
        try store.locked {
            _ = try owned(id)
            let saved: BrightnessSnapshot
            if let previous = try store.read(BrightnessSnapshot.self, at: store.brightnessURL) {
                saved = previous
            } else {
                saved = try brightness.snapshot()
                try store.write(saved, to: store.brightnessURL)
                store.log("brightness_saved")
            }
            let target = min(saved.brightness, Self.minimumBrightness)
            if abs(try brightness.current(for: saved.displayUUID) - target) > 0.003 {
                try brightness.set(target, for: saved.displayUUID)
            }
            guard abs(try brightness.current(for: saved.displayUUID) - target) <= 0.015 else {
                throw InsoniaFailure("error.minimumBrightness")
            }
        }
    }

    func restore(id: String) throws {
        try store.locked { _ = try owned(id); try restoreBrightnessLocked() }
    }

    func end(id: String?, reason: InsoniaFailure? = nil) throws {
        try store.locked {
            if let id { _ = try owned(id) }
            try endLocked(reason: reason)
        }
    }

    func guardianWillTerminate() throws {
        try store.locked {
            if try store.read(SessionLease.self, at: store.sessionURL) != nil {
                try endLocked(reason: "recovery.guardianExit")
            } else {
                try restoreBrightnessLocked()
            }
        }
    }

    func recoverIfNeeded(now: @autoclosure () -> TimeInterval, processAlive: (Int32) -> Bool, safety: SafetyReading) throws {
        try store.locked {
            let lease: SessionLease?
            do { lease = try store.read(SessionLease.self, at: store.sessionURL) }
            catch {
                try endLocked(reason: "recovery.invalidSession")
                return
            }
            guard let lease else {
                // Orphaned brightness is retried independently of system-sleep recovery.
                try restoreBrightnessLocked()
                return
            }
            let reason = safety.stopReason ?? (!processAlive(lease.pid)
                ? "recovery.crash"
                // Sample time after obtaining the lock and reading the lease. A
                // renewal queued ahead of us may be newer than a pre-lock clock.
                : (!LeasePolicy.isFresh(heartbeat: lease.heartbeatUptime, now: now())
                    ? "recovery.stall" : nil))
            if let reason { try endLocked(reason: reason) }
        }
    }

    private func owned(_ id: String) throws -> SessionLease {
        guard let lease = try store.read(SessionLease.self, at: store.sessionURL), lease.id == id else {
            throw InsoniaFailure("error.sessionRecovered")
        }
        return lease
    }

    private func endLocked(reason: InsoniaFailure?) throws {
        // Restore while the machine is still awake. Preserve the journal on failure.
        var failure: Error?
        do { try restoreBrightnessLocked() } catch { failure = error }
        try? store.remove(store.heartbeatURL)
        do { try store.requestSleepDisabled(false) } catch { failure = error }
        if let reason {
            let notice = RecoveryNotice(date: Date(), reason: reason)
            // Keep the old lease until this safety intent is durable. If storage
            // is full, the guardian can retry and autostart still sees a session.
            try store.write(["createdAt": notice.date.timeIntervalSince1970], to: store.autostartBlockURL)
            do { try store.write(notice, to: store.noticeURL) } catch { failure = error }
        }
        try store.remove(store.sessionURL)
        store.log("session_ended" + (reason.map { " recovery=true reason=\($0.key)" } ?? ""))
        if let failure { throw failure }
    }

    private func restoreBrightnessLocked() throws {
        guard let saved = try store.read(BrightnessSnapshot.self, at: store.brightnessURL) else { return }
        try brightness.set(saved.brightness, for: saved.displayUUID)
        guard abs(try brightness.current(for: saved.displayUUID) - saved.brightness) <= 0.015 else {
            throw InsoniaFailure("error.restoreBrightness")
        }
        try store.remove(store.brightnessURL)
        store.log("brightness_restored")
    }
}

/// A recovery attempt and the guardian's liveness receipt are independent.
/// A failed restore publishes a degraded receipt and retains the journal.
final class GuardianCycle {
    let coordinator: SessionCoordinator
    init(coordinator: SessionCoordinator) { self.coordinator = coordinator }

    func tick(safety: SafetyReading, processAlive: (Int32) -> Bool,
              uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, pid: Int32 = getpid()) throws {
        var failure: InsoniaFailure?
        do { try coordinator.recoverIfNeeded(now: uptime(), processAlive: processAlive, safety: safety) }
        catch {
            failure = InsoniaFailure.wrapping(error)
            coordinator.store.log("guardian_recovery_pending reason=\(failure!.key)")
        }
        try coordinator.store.write(GuardianPulse(version: RuntimeStore.guardianVersion,
            pid: pid, uptime: uptime(), recoveryFailure: failure), to: coordinator.store.guardianURL, durable: false)
    }
}

final class InstanceLock {
    private var fd: Int32 = -1
    func acquire(at url: URL) throws -> Bool {
        fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw InsoniaFailure("error.instanceLock") }
        return flock(fd, LOCK_EX | LOCK_NB) == 0
    }
    deinit { if fd >= 0 { close(fd) } }
}
