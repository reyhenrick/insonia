import Foundation
import Darwin

let store = RuntimeStore()
let coordinator = SessionCoordinator(store: store, brightness: DisplayBrightness())
let cycle = GuardianCycle(coordinator: coordinator)
let lock = InstanceLock()
let sessionActivity = SessionActivity()
do {
    try store.prepare()
    guard try lock.acquire(at: store.runtime.appendingPathComponent("guardian.lock")) else { exit(0) }
} catch { exit(1) }

// launchd restarts the guardian after a crash. The root heartbeat watchdog also
// re-enables normal sleep if the entire user session is terminated.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let shutdown = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
shutdown.setEventHandler {
    try? coordinator.guardianWillTerminate()
    exit(0)
}
shutdown.resume()

while true {
    autoreleasepool {
        do {
            if FileManager.default.fileExists(atPath: store.sessionURL.path) {
                sessionActivity.start()
            } else {
                sessionActivity.stop()
            }
            try cycle.tick(safety: MacState.safety, processAlive: MacState.processExists)
        } catch {
            // Journal remains durable. A later tick retries display restoration.
            store.log("guardian_pulse_write_failed reason=\(InsoniaFailure.wrapping(error).key)")
        }
    }
    Thread.sleep(forTimeInterval: 2)
}
