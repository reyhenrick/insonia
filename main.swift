import AppKit
import Combine
import SwiftUI

/// Hospeda SwiftUI dentro do botão do status item sem roubar o clique.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @MainActor required init(rootView: Content) { super.init(rootView: rootView) }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// `NSPanel` em vez de `NSPopover`: o popover desenha a própria caixa opaca com
/// seta (que briga com o vidro) e posiciona sozinho — media 63pt abaixo da barra
/// aqui, sem respeitar `preferredEdge`. Com o painel, a posição é conta nossa e
/// o fundo pode ser transparente para o Liquid Glass ser a superfície inteira.
final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let core = PowerCore()
    private lazy var updater = AppUpdater(core: core)
    private var watchers: Set<AnyCancellable> = []
    private var dismissMonitor: Any?
    /// Guardado porque o tamanho útil vem da hosting view; o container só
    /// existe para mascarar o canto, e o `fittingSize` dele não propaga.
    private var hostView: NSView?
    private var previewWindow: NSWindow?

    private func makePanelView() -> PanelView {
        PanelView(core: core, updater: updater, onQuit: { [weak self] in self?.quit() })
    }

    private lazy var panel: PanelWindow = {
        let panel = PanelWindow(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // A sombra do sistema segue o alfa da janela. Mascarando a camada no
        // raio do painel, o alfa já sai arredondado e o compositor desenha a
        // sombra certa na GPU — sem quadrado e sem rasterizar nada por frame.
        let host = NSHostingView(rootView: makePanelView())
        host.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = PanelView.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
        hostView = host
        return panel
    }()

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        if CommandLine.arguments.contains("--agents") { core.setAgentsEnabled(true) }
        core.start(resumeActive: CommandLine.arguments.contains("--resume-active"))
        updater.hidePanel = { [weak self] in self?.hidePanel() }
        updater.showPanel = { [weak self] in self?.showPanel() }
        updater.start()

        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            installIcon(in: button)
            button.toolTip = "Insonia"
            button.setAccessibilityLabel("Insonia")
        }

        core.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.refreshTooltip()
                if self?.panel.isVisible == true { self?.layoutPanel() }
            }
            .store(in: &watchers)
        updater.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.refreshTooltip()
                if self?.panel.isVisible == true { self?.layoutPanel() }
            }
            .store(in: &watchers)
        refreshTooltip()

        // Abre o painel sozinho ao iniciar — serve para inspecionar a UI sem
        // depender de permissão de Acessibilidade para clicar no ícone.
        if CommandLine.arguments.contains("--preview-window") {
            DispatchQueue.main.async { [weak self] in self?.showPreviewWindow() }
        } else if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showPanel()
            }
        }
    }

    /// `disablesleep` é estado persistente do sistema: se sairmos sem reverter,
    /// o Mac fica acordado para sempre e ninguém desfaz.
    func applicationWillTerminate(_ note: Notification) {
        core.shutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Keep the authorization callback alive until it has finished all cleanup.
        updater.terminationReply()
    }

    // MARK: - barra de menu

    /// O ícone é uma view SwiftUI hospedada para poder usar `symbolEffect`;
    /// `NSImage` não anima.
    @MainActor private func installIcon(in button: NSStatusBarButton) {
        let host = PassthroughHostingView(rootView: StatusIcon(core: core, updater: updater))
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
    }

    private func refreshTooltip() {
        statusItem.button?.toolTip = "Insonia: \(core.status)"
            + (updater.updateAvailable ? " · " + L10n.text("ui.updateAvailable") : "")
    }

    @objc private func statusItemClicked() {
        // Botão direito alterna direto, sem abrir o painel.
        if NSApp.currentEvent?.type == .rightMouseUp {
            core.toggle()
            return
        }
        panel.isVisible ? hidePanel() : showPanel()
    }

    // MARK: - painel

    private func showPanel() {
        layoutPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        startDismissMonitor()
    }

    private func layoutPanel() {
        // Âncora pelos bounds do botão convertidos para a tela, não pelo frame
        // da janela do status item: a janela pode estar deslocada do ícone que
        // ela desenha (medi 66pt de diferença), e o painel sai torto.
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))

        panel.layoutIfNeeded()
        var size = hostView?.fittingSize ?? .zero
        if size.width < 1 || size.height < 1 { size = NSSize(width: 320, height: 300) }
        panel.setContentSize(size)

        let gap: CGFloat = 6
        var x = anchor.midX - size.width / 2
        let y = anchor.minY - gap - size.height
        if let visible = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.invalidateShadow()
    }

    private func hidePanel() {
        panel.orderOut(nil)
        stopDismissMonitor()
    }

    private func showPreviewWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("ui.preview")
        window.contentViewController = NSHostingController(rootView: makePanelView())
        window.isReleasedWhenClosed = false
        window.center()
        previewWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Fecha ao clicar fora. O clique no próprio ícone é ignorado aqui, senão o
    /// monitor fecha e a ação do botão reabre no mesmo clique.
    private func startDismissMonitor() {
        guard dismissMonitor == nil else { return }
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            if self.statusItem.button?.window?.frame.contains(point) == true { return }
            if self.panel.frame.contains(point) { return }
            self.hidePanel()
        }
    }

    private func stopDismissMonitor() {
        if let monitor = dismissMonitor { NSEvent.removeMonitor(monitor) }
        dismissMonitor = nil
    }

    private func quit() {
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--diagnostics") {
    let store = RuntimeStore()
    let lease = try? store.read(SessionLease.self, at: store.sessionURL)
    let safety = MacState.safety
    let brightness = try? DisplayBrightness().snapshot()
    let info: [String: Any] = [
        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        "language": L10n.language, "helperReady": MacState.helperReady,
        "guardianHealthy": GuardianManager.healthy(store: store),
        "guardianState": GuardianManager.health(store: store).state.rawValue,
        "guardianPulseAgeSeconds": GuardianManager.health(store: store).age as Any? ?? NSNull(),
        "recoveryReason": (try? store.read(RecoveryNotice.self, at: store.noticeURL))?.reason.key as Any? ?? NSNull(),
        "sleepDisabled": MacState.sleepDisabled, "lidClosed": MacState.lidClosed as Any? ?? NSNull(),
        "sessionAvailable": MacState.sessionAvailable, "displayAvailable": DisplayBrightness.usableDisplay,
        "onBattery": safety.onBattery, "batteryPercent": safety.batteryPercent as Any? ?? NSNull(),
        "thermalState": safety.thermalState.rawValue, "mode": lease?.mode.rawValue as Any? ?? NSNull(),
        "heartbeatAgeSeconds": lease.map { ProcessInfo.processInfo.systemUptime - $0.heartbeatUptime } as Any? ?? NSNull(),
        "brightness": brightness?.brightness as Any? ?? NSNull(),
        "brightnessRecoveryPending": FileManager.default.fileExists(atPath: store.brightnessURL.path)
    ]
    if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    exit(0)
}

// Take ownership before constructing PowerCore or touching global energy state.
let instanceStore = RuntimeStore()
let instanceLock = InstanceLock()
do {
    try instanceStore.prepare()
    guard try instanceLock.acquire(at: instanceStore.runtime.appendingPathComponent("app.lock")) else { exit(0) }
} catch {
    FileHandle.standardError.write(Data("Insonia: \(error.localizedDescription)\n".utf8))
    exit(1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
