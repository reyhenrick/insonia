import Foundation

enum LidMode: String, Codable {
    case background, agents
}

struct SafetyReading {
    var onBattery: Bool
    var batteryPercent: Int?
    var thermalState: ProcessInfo.ThermalState

    var stopReason: InsoniaFailure? {
        if thermalState == .serious || thermalState == .critical {
            return "safety.thermal"
        }
        if onBattery, let batteryPercent, batteryPercent <= 15 {
            return InsoniaFailure("safety.battery", String(batteryPercent))
        }
        if onBattery && batteryPercent == nil {
            return "safety.unknownBattery"
        }
        return nil
    }
}

enum LeasePolicy {
    static let timeout: TimeInterval = 30
    static func isFresh(heartbeat: TimeInterval, now: TimeInterval) -> Bool {
        heartbeat.isFinite && now.isFinite && now >= heartbeat && now - heartbeat <= timeout
    }
}

/// Keep the session controller schedulable even when the lid hides all UI.
/// The token does not inhibit system sleep: the expiring root lease owns that.
final class SessionActivity {
    private var token: NSObjectProtocol?
    private let beginActivity: () -> NSObjectProtocol
    private let endActivity: (NSObjectProtocol) -> Void

    init(begin: @escaping () -> NSObjectProtocol = {
        ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Insonia: maintain and supervise the user-requested session")
    }, end: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }) {
        beginActivity = begin
        endActivity = end
    }

    func start() { if token == nil { token = beginActivity() } }
    func stop() {
        if let token { endActivity(token); self.token = nil }
    }
    deinit { stop() }
}
