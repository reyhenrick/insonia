import Foundation

/// Installation is permitted only after the operating system and both recovery
/// journals confirm an idle session. A missing OS reading is not confirmation.
struct UpdateReadiness: Equatable {
    var sessionActive = false
    var protectionBusy = false
    var stopPending = false
    var persistedSession = false
    var brightnessPending = false
    var guardianRecovering = false
    var sleepDisabled: Bool? = nil
    var normalSleepConfirmed = false

    var canInstall: Bool {
        !sessionActive && !protectionBusy && !stopPending && !persistedSession
            && !brightnessPending && !guardianRecovering && sleepDisabled == false && normalSleepConfirmed
    }
}

enum LaunchPolicy {
    static func shouldActivate(preference: Bool, resumeRequested: Bool,
                               updateRelaunch: Bool, recoveryNoticePresent: Bool) -> Bool {
        !updateRelaunch && !recoveryNoticePresent && (preference || resumeRequested)
    }
}

/// Retain one continuation until safe. Remove it before invocation so a callback
/// can enqueue the next installer stage without invoking either stage twice.
final class UpdateInstallGate {
    private var continuation: (() -> Void)?
    var isWaiting: Bool { continuation != nil }

    func enqueue(_ continuation: @escaping () -> Void) { self.continuation = continuation }
    func cancel() { continuation = nil }

    @discardableResult
    func advance(readiness: UpdateReadiness, prepare: () throws -> Void) throws -> Bool {
        guard readiness.canInstall, let next = continuation else { return false }
        try prepare()
        continuation = nil
        next()
        return true
    }
}

/// Retry preparation even if readiness became stable during backoff. Depending
/// only on a future readiness change would strand an otherwise ready update.
final class UpdateRetryScheduler {
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> (() -> Void)
    private let clock: () -> TimeInterval
    private let schedule: Schedule
    private var cancellation: (() -> Void)?
    private var generation = 0
    private var nextAttempt: TimeInterval = 0
    var isReady: Bool { clock() >= nextAttempt }

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping Schedule = { delay, action in
             let work = DispatchWorkItem(block: action)
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
             return { work.cancel() }
         }) {
        self.clock = clock
        self.schedule = schedule
    }

    func retry(after delay: TimeInterval, action: @escaping () -> Void) {
        cancel()
        nextAttempt = clock() + delay
        let expected = generation
        cancellation = schedule(delay) { [weak self] in
            guard let self, self.generation == expected else { return }
            self.generation += 1
            self.nextAttempt = 0
            self.cancellation = nil
            action()
        }
    }

    func cancel() {
        generation += 1
        cancellation?()
        cancellation = nil
        nextAttempt = 0
    }

    deinit { cancellation?() }
}
