// Explicit integration probe. Runs only on request; uses the real guardian/helper.
import Foundation
import Darwin

@main struct LiveRecoveryProbe {
    static func report(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
    static func main() {
        let mode = CommandLine.arguments.dropFirst().first ?? "normal"
        guard ["normal", "crash", "stall", "root-watchdog"].contains(mode) else { exit(2) }
        let store = RuntimeStore()
        let display = DisplayBrightness()
        let coordinator = SessionCoordinator(store: store, brightness: display)
        var id: String?
        do {
            guard MacState.helperReady, GuardianManager.healthy(store: store),
                  MacState.lidClosed == false, MacState.sessionAvailable else {
                throw InsoniaFailure("Live probe requires ready services, lid open, and an unlocked session.")
            }
            let revision = try store.protectiveStopRevision()
            let lease = try coordinator.begin(mode: .agents, expectedProtectiveRevision: revision)
            id = lease.id
            let deadline = ProcessInfo.processInfo.systemUptime + 15
            while !MacState.helperConfirmed(sessionID: lease.id) {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw InsoniaFailure("No helper receipt") }
                try coordinator.renew(id: lease.id, mode: .agents)
                Thread.sleep(forTimeInterval: 0.2)
            }
            let before = try display.snapshot()
            report(["event": "started", "pid": getpid(), "mode": mode, "originalBrightness": before.brightness])
            if mode == "normal" || mode == "crash" {
                try coordinator.dim(id: lease.id)
                report(["event": "dimmed", "brightness": try display.current(for: before.displayUUID)])
            }
            if mode == "crash" { _exit(73) }
            if mode == "root-watchdog" {
                let expires = ProcessInfo.processInfo.systemUptime + 50
                while MacState.sleepDisabled && ProcessInfo.processInfo.systemUptime < expires {
                    Thread.sleep(forTimeInterval: 0.2)
                }
                guard !MacState.sleepDisabled else { throw InsoniaFailure("Root watchdog did not expire the lease") }
                guard try store.read(SessionLease.self, at: store.sessionURL)?.id == lease.id else {
                    throw InsoniaFailure("Guardian handled recovery instead of root watchdog")
                }
                report(["event": "root_watchdog_recovered", "sleepDisabled": MacState.sleepDisabled])
                try coordinator.end(id: lease.id)
                id = nil
            } else if mode == "stall" {
                let expires = ProcessInfo.processInfo.systemUptime + 45
                while ProcessInfo.processInfo.systemUptime < expires {
                    if try store.read(SessionLease.self, at: store.sessionURL) == nil { break }
                    Thread.sleep(forTimeInterval: 0.2)
                }
                guard try store.read(SessionLease.self, at: store.sessionURL) == nil else {
                    throw InsoniaFailure("Guardian did not expire stalled probe")
                }
                id = nil
                report(["event": "stall_recovered", "brightness": try display.current(for: before.displayUUID)])
            } else {
                Thread.sleep(forTimeInterval: 1)
                try coordinator.end(id: lease.id)
                id = nil
                report(["event": "restored", "brightness": try display.current(for: before.displayUUID)])
            }
        } catch {
            if let id { try? coordinator.end(id: id) }
            report(["event": "error", "message": error.localizedDescription])
            exit(1)
        }
    }
}
