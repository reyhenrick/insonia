import AppKit
import Sparkle

/// Optional Objective-C delegate methods can compile with a misspelled Swift
/// name while silently never being called. Check the actual runtime selectors.
@main
struct UpdaterContractTests {
    @MainActor static func main() {
        let updater = AppUpdater(core: PowerCore())
        let selectors = [
            "updater:mayPerformUpdateCheck:error:",
            "updater:didFindValidUpdate:",
            "updater:shouldProceedWithUpdate:updateCheck:error:",
            "updater:didExtractUpdate:",
            "updater:willInstallUpdateOnQuit:immediateInstallationBlock:",
            "updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:",
            "updater:willInstallUpdate:",
            "updater:didAbortWithError:",
            "supportsGentleScheduledUpdateReminders",
            "standardUserDriverWillHandleShowingUpdate:forUpdate:state:",
            "standardUserDriverWillFinishUpdateSession",
            "standardUserDriverWillShowModalAlert",
        ]
        for name in selectors {
            guard updater.responds(to: NSSelectorFromString(name)) else {
                fputs("FAIL: missing Sparkle delegate selector \(name)\n", stderr)
                exit(1)
            }
        }
        // Merely constructing the model does not start networking or services.
        guard !updater.canPerformUpdateAction, !updater.updateAvailable else { exit(1) }
        print("PASS: \(selectors.count) Sparkle delegate contracts; updater remains stopped until start")
        let comparator = SUStandardVersionComparator.default
        for previous in ["5", "6"] {
            guard comparator.compareVersion("7", toVersion: previous) == .orderedDescending else {
                fputs("FAIL: build 7 must update installed build \(previous)\n", stderr)
                exit(1)
            }
        }
        print("PASS: build 7 supersedes both previous public builds using Sparkle's comparator")
    }
}
