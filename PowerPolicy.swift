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

struct HelperReceipt {
    let version: Int
    let timestamp: TimeInterval
    let sleepDisabled: Bool
    let sessionID: String

    init?(_ value: String) {
        let fields = value.split(whereSeparator: { $0.isWhitespace })
        guard fields.count == 4, let version = Int(fields[0]), [2, 3].contains(version),
              let timestamp = TimeInterval(fields[1]), timestamp.isFinite,
              timestamp >= 0, timestamp.rounded(.down) == timestamp,
              fields[2] == "0" || fields[2] == "1" else { return nil }
        let disabled = fields[2] == "1"
        let token = String(fields[3])
        guard disabled ? UUID(uuidString: token) != nil : token == "-" else { return nil }
        self.version = version
        self.timestamp = timestamp
        self.sleepDisabled = disabled
        self.sessionID = token
    }

    func isRecent(now: TimeInterval) -> Bool {
        now.isFinite && now >= timestamp && now - timestamp <= 25
    }

    func confirmsNormalSleep(after request: TimeInterval, now: TimeInterval) -> Bool {
        // Receipts have second precision. Require a strictly later receipt so
        // a stale zero from before a rapid activation/stop cannot pass the gate.
        !sleepDisabled && isRecent(now: now) && timestamp > request
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
