import AppKit
import Combine
import Sparkle

/// Sparkle owns scheduling, downloading, signatures, replacement and rollback.
/// Insonia owns the boundary at which its power session is safe to replace.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var automaticallyInstalls = false
    @Published private(set) var waitingForIdle = false
    @Published private(set) var lastError: String?

    private let core: PowerCore
    private let gate = UpdateInstallGate()
    private var watchers: Set<AnyCancellable> = []
    private var started = false
    private var automaticUpdateQueued = false
    private var stagedUpdateMayInstall = false
    private var installationRequested = false
    private var terminationPending = false
    private let preparationRetry = UpdateRetryScheduler()
    private enum GatePurpose { case automatic, manual }
    private var gatePurpose: GatePurpose = .manual
    var hidePanel: (() -> Void)?
    var showPanel: (() -> Void)?

    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false,
        updaterDelegate: self, userDriverDelegate: self)

    init(core: PowerCore) {
        self.core = core
        super.init()
    }

    func start() {
        guard !started else { return }
        guard core.installedInApplications else { return }
        started = true
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$automaticallyInstalls)
        core.$updateReadiness
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.attemptPendingInstallation() }
            .store(in: &watchers)
        do { try updater.start() }
        catch { lastError = L10n.text("error.updateStart", error.localizedDescription) }
    }

    func checkForUpdates() {
        guard started else { lastError = L10n.text("error.updateUnavailable"); return }
        guard !core.installingHelper, !core.repairingGuardian, !core.preparingUpdate else {
            lastError = L10n.text("error.updateBusy")
            return
        }
        if automaticUpdateQueued && gate.isWaiting && gatePurpose == .automatic {
            gatePurpose = .manual
            attemptPendingInstallation()
            return
        }
        guard canCheckForUpdates else { return }
        lastError = nil
        hidePanel?()
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyInstalls(_ enabled: Bool) {
        guard started else { return }
        controller.updater.automaticallyDownloadsUpdates = enabled
        if enabled { attemptPendingInstallation() }
    }

    var canPerformUpdateAction: Bool {
        canCheckForUpdates || (automaticUpdateQueued && gate.isWaiting && gatePurpose == .automatic)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// AppKit also receives ordinary Quit events while Sparkle has a staged
    /// automatic update. Those need the same completed power recovery barrier.
    func terminationReply() -> NSApplication.TerminateReply {
        if core.installingHelper || core.repairingGuardian { return .terminateCancel }
        guard installationRequested || automaticUpdateQueued || stagedUpdateMayInstall || gate.isWaiting || core.preparingUpdate else { return .terminateNow }
        if core.preparingUpdate && core.captureUpdateReadiness().canInstall { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        if !installationRequested {
            // This is an ordinary user Quit, not an updater-initiated restart.
            // It explicitly ends the session before the queued update can install.
            core.stopForUpdateTermination()
        }
        waitingForIdle = true
        DispatchQueue.main.async { [weak self] in self?.attemptPendingInstallation() }
        return .terminateLater
    }

    private func enqueueInstallation(_ handler: @escaping () -> Void, automatic: Bool = false) {
        gatePurpose = automatic ? .automatic : .manual
        gate.enqueue(handler)
        waitingForIdle = true
        DispatchQueue.main.async { [weak self] in self?.attemptPendingInstallation() }
    }

    private func attemptPendingInstallation() {
        guard (gate.isWaiting || terminationPending), preparationRetry.isReady else { return }
        if !terminationPending && gatePurpose == .automatic && !controller.updater.automaticallyDownloadsUpdates { return }
        let readiness = core.captureUpdateReadiness()
        guard readiness.canInstall else { waitingForIdle = true; return }
        do {
            if terminationPending {
                try core.prepareForUpdate()
                preparationRetry.cancel()
                terminationPending = false
                gate.cancel()
                waitingForIdle = false
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            try gate.advance(readiness: readiness) { try core.prepareForUpdate() }
            preparationRetry.cancel()
            waitingForIdle = gate.isWaiting
        } catch {
            preparationRetry.retry(after: 10) { [weak self] in self?.attemptPendingInstallation() }
            lastError = InsoniaFailure.wrapping(error).message
            if terminationPending {
                terminationPending = false
                // Keep the original installation continuation. A cancelled Quit
                // must not strand the update behind a discarded one-shot block.
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard core.installedInApplications else { throw InsoniaFailure("error.updateUnavailable") }
        guard !core.installingHelper, !core.repairingGuardian, !core.preparingUpdate else {
            throw InsoniaFailure("error.updateBusy")
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailable = true
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) throws {
        if updateCheck != .updateInformation {
            // This delegate can veto the update. Make relaunch intent durable
            // before downloading/extracting can create an external installer.
            try core.notePotentialUpdate()
        }
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        // Sparkle's external installer can finish on any app exit after this
        // point, even before the user chooses Install and Relaunch.
        stagedUpdateMayInstall = true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock handler: @escaping () -> Void) -> Bool {
        automaticUpdateQueued = true
        updateAvailable = true
        enqueueInstallation(handler, automatic: true)
        return true
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock handler: @escaping () -> Void) -> Bool {
        if core.preparingUpdate && core.captureUpdateReadiness().canInstall { return false }
        enqueueInstallation(handler)
        if !core.captureUpdateReadiness().canInstall { showPanel?() }
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        // Sparkle sends this once, before its external helper sends the Quit event.
        // Keep the latch across a cancelled termination; retries may skip it.
        installationRequested = true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        gate.cancel()
        preparationRetry.cancel()
        waitingForIdle = false
        installationRequested = false
        automaticUpdateQueued = false
        core.cancelUpdatePreparation()
        if terminationPending {
            terminationPending = false
            NSApp.reply(toApplicationShouldTerminate: false)
        }
        if nsError.domain == SUSparkleErrorDomain && [1001, 4007].contains(nsError.code) {
            if nsError.code == 1001 { updateAvailable = false }
            return
        }
        // Sparkle presents actionable errors for manual checks in the user's language.
        // Background connectivity errors do not become permanent power warnings.
        lastError = nil
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        updateAvailable = true
        if state.userInitiated { hidePanel?() }
    }

    func standardUserDriverWillFinishUpdateSession() {
        if !automaticUpdateQueued && !installationRequested && !gate.isWaiting { updateAvailable = false }
    }

    func standardUserDriverWillShowModalAlert() { hidePanel?() }
}
