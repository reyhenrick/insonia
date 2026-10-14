import AppKit
import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps
import Darwin

final class DisplayBrightness: BrightnessControlling {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private let library: UnsafeMutableRawPointer?
    private let getter: GetBrightness?
    private let setter: SetBrightness?

    init() {
        library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)
        if let library, let get = dlsym(library, "DisplayServicesGetBrightness"),
           let set = dlsym(library, "DisplayServicesSetBrightness") {
            getter = unsafeBitCast(get, to: GetBrightness.self)
            setter = unsafeBitCast(set, to: SetBrightness.self)
        } else { getter = nil; setter = nil }
    }

    deinit { if let library { dlclose(library) } }

    static func displays() -> [CGDirectDisplayID] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    static func uuid(_ display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
    }

    static var usableDisplay: Bool {
        displays().contains { CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0 }
    }

    func snapshot() throws -> BrightnessSnapshot {
        guard getter != nil, setter != nil else {
            throw InsoniaFailure("error.brightnessUnsupported")
        }
        guard let display = Self.displays().first(where: { CGDisplayIsBuiltin($0) != 0 }),
              let uuid = Self.uuid(display) else {
            throw InsoniaFailure("error.builtInDisplay")
        }
        return BrightnessSnapshot(displayUUID: uuid, brightness: try current(for: uuid))
    }

    private func display(for uuid: String) throws -> CGDirectDisplayID {
        guard let display = Self.displays().first(where: { Self.uuid($0) == uuid && CGDisplayIsBuiltin($0) != 0 }) else {
            throw InsoniaFailure("error.displayReturning")
        }
        return display
    }

    func current(for displayUUID: String) throws -> Float {
        guard let getter else { throw InsoniaFailure("error.brightnessRead") }
        var value: Float = 0
        let result = getter(try display(for: displayUUID), &value)
        guard result == 0, value.isFinite, (0...1).contains(value) else {
            throw InsoniaFailure("error.brightnessUnconfirmed", String(result))
        }
        return value
    }

    func set(_ value: Float, for displayUUID: String) throws {
        guard let setter, value.isFinite, (0...1).contains(value) else {
            throw InsoniaFailure("error.brightnessUnavailable")
        }
        let result = setter(try display(for: displayUUID), value)
        guard result == 0 else { throw InsoniaFailure("error.brightnessSet", String(result)) }
    }
}

enum MacState {
    static func rootProperty(_ name: String) -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    static var sleepDisabled: Bool { rootProperty("SleepDisabled") == true }
    static var lidClosed: Bool? { rootProperty("AppleClamshellState") }

    static var sessionAvailable: Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any],
              dictionary[kCGSessionOnConsoleKey as String] as? Bool == true,
              dictionary[kCGSessionLoginDoneKey as String] as? Bool == true else { return false }
        // Supplement public console state with the system's observed lock indicator.
        // The lock notification is also latched by PowerCore; never unlock a session.
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        var consoleLocked = false
        if root != 0 {
            consoleLocked = IORegistryEntryCreateCFProperty(root, "IOConsoleLocked" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool == true
            IOObjectRelease(root)
        }
        return !consoleLocked && dictionary["CGSSessionScreenIsLocked"] as? Bool != true
    }

    static var safety: SafetyReading {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let provider = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = provider == kIOPSBatteryPowerValue
        var percent: Int?
        if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                percent = max(0, min(100, capacity * 100 / maximum))
            }
        }
        // Unknown provider on a portable is not evidence of external power.
        return SafetyReading(onBattery: onBattery || provider == nil,
            batteryPercent: percent, thermalState: ProcessInfo.processInfo.thermalState)
    }

    static var helperReady: Bool {
        let version = try? String(contentsOfFile: "/Library/PrivilegedHelperTools/com.henrick.insonia/version", encoding: .utf8)
        guard version?.trimmingCharacters(in: .whitespacesAndNewlines) == String(RuntimeStore.helperVersion),
              let receipt = try? String(contentsOfFile: "/var/run/insonia-helper-v3-status", encoding: .utf8) else { return false }
        let fields = receipt.split(whereSeparator: { $0.isWhitespace })
        guard fields.count == 4, fields[0] == "3", let stamp = TimeInterval(fields[1]) else { return false }
        let age = Date().timeIntervalSince1970 - stamp
        return age >= 0 && age <= 25
    }

    static func helperConfirmed(sessionID: String) -> Bool {
        guard helperReady, sleepDisabled,
              let receipt = try? String(contentsOfFile: "/var/run/insonia-helper-v3-status", encoding: .utf8) else { return false }
        let fields = receipt.split(whereSeparator: { $0.isWhitespace })
        return fields.count == 4 && fields[2] == "1" && fields[3] == sessionID
    }

    static func processExists(_ pid: Int32) -> Bool { pid > 1 && (kill(pid, 0) == 0 || errno == EPERM) }
}

final class DisplayActivity {
    private var displayAssertion: IOPMAssertionID = 0
    private var activityAssertion: IOPMAssertionID = 0
    private var lastActivity: TimeInterval = -.infinity

    func maintain(lidClosed: Bool) throws {
        if displayAssertion == 0 {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Insonia: display available to agents" as CFString,
                &displayAssertion)
            guard result == kIOReturnSuccess else {
                displayAssertion = 0
                throw InsoniaFailure("error.displayAssertion", String(result))
            }
        }
        // Public user activity does not guarantee lid-close behavior. Arm it while
        // open and retain the display assertion; verify the real display after close.
        let now = ProcessInfo.processInfo.systemUptime
        if !lidClosed && now - lastActivity >= 15 {
            let result = IOPMAssertionDeclareUserActivity("Insonia: agent session" as CFString,
                kIOPMUserActiveLocal, &activityAssertion)
            guard result == kIOReturnSuccess else { throw InsoniaFailure("error.sessionAssertion") }
            lastActivity = now
        }
    }

    func release() {
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); displayAssertion = 0 }
        if activityAssertion != 0 { IOPMAssertionRelease(activityAssertion); activityAssertion = 0 }
        lastActivity = -.infinity
    }

    deinit { release() }
}

enum LocalProcess {
    @discardableResult static func run(_ path: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + 5) == .timedOut {
            if process.isRunning { process.terminate() }
            throw InsoniaFailure("error.processTimeout")
        }
        return process.terminationStatus
    }
}

enum GuardianManager {
    static let label = "com.henrick.insonia.guardian"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func install(bundle: Bundle = .main, restartUnresponsive: Bool = false) throws {
        let executable = bundle.bundleURL.appendingPathComponent("Contents/Helpers/InsoniaGuard").path
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw InsoniaFailure("error.guardianMissing")
        }
        let job: [String: Any] = ["Label": label, "ProgramArguments": [executable],
            "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 5,
            "ProcessType": "Background", "ExitTimeOut": 5,
            "EnvironmentVariables": ["INSONIA_GUARDIAN_VERSION": String(RuntimeStore.guardianVersion)]]
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
        let changed = (try? Data(contentsOf: plistURL)) != data
        if changed { try data.write(to: plistURL, options: .atomic) }
        let domain = "gui/\(getuid())"
        var registered = try LocalProcess.run("/bin/launchctl", ["print", "\(domain)/\(label)"]) == 0
        if registered && (changed || restartUnresponsive) {
            guard try LocalProcess.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"]) == 0 else {
                throw InsoniaFailure("error.guardianInstall")
            }
            registered = false
        }
        if !registered {
            _ = try LocalProcess.run("/bin/launchctl", ["enable", "\(domain)/\(label)"])
            guard try LocalProcess.run("/bin/launchctl", ["bootstrap", domain, plistURL.path]) == 0 else {
                throw InsoniaFailure("error.guardianInstall")
            }
        }
    }

    static func healthy(store: RuntimeStore) -> Bool {
        health(store: store).ready
    }

    static func health(store: RuntimeStore) -> GuardianHealth {
        do {
            let pulse = try store.read(GuardianPulse.self, at: store.guardianURL)
            // Sample the clock after reading the pulse, as for the session lease.
            return GuardianHealth.evaluate(pulse, now: ProcessInfo.processInfo.systemUptime,
                processAlive: MacState.processExists)
        } catch { return GuardianHealth(state: .unreadable, age: nil, failure: InsoniaFailure.wrapping(error)) }
    }

    static func uninstall() throws {
        let domain = "gui/\(getuid())/\(label)"
        if try LocalProcess.run("/bin/launchctl", ["print", domain]) == 0 {
            guard try LocalProcess.run("/bin/launchctl", ["bootout", domain]) == 0 else {
                throw InsoniaFailure("error.guardianInstall")
            }
        }
        if FileManager.default.fileExists(atPath: plistURL.path) { try FileManager.default.removeItem(at: plistURL) }
    }
}
