import Combine
import SwiftUI

struct StatusIcon: View {
    @ObservedObject var core: PowerCore
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Image(systemName: core.active ? "bolt.fill" : "bolt.slash")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: core.active)
            .frame(width: 22, height: 22)
            .overlay(alignment: .bottomTrailing) {
                if updater.updateAvailable { Circle().fill(.blue).frame(width: 5, height: 5) }
            }
    }
}

struct PanelView: View {
    static let cornerRadius: CGFloat = 22

    @ObservedObject var core: PowerCore
    @ObservedObject var updater: AppUpdater
    var onQuit: () -> Void

    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            mainControl
            Text(core.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            preferences
                .disabled(core.preparingUpdate)
            if let notice = core.recoveryNotice {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.text("ui.previousInterruption"), systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                    Text(notice.message)
                        .fixedSize(horizontal: false, vertical: true)
                    if core.guardianReady && !core.helperNeeded {
                        Text(L10n.text("ui.readyAgain"))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text(notice.date, style: .date).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.text("ui.acknowledge"), action: core.acknowledgeRecovery)
                    }
                }
                .font(.caption)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }
            if let error = core.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
            if updater.waitingForIdle {
                Text(L10n.text(core.updateReadiness.sessionActive ? "ui.updateWaiting" : "error.updateRecovery"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = updater.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 380)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        .onReceive(clock) { if core.active { now = $0 } }
    }

    private var header: some View {
        HStack {
            Label("Insonia", systemImage: "bolt.fill")
                .font(.headline)
            Spacer()
        }
    }

    private var mainControl: some View {
        Toggle(isOn: Binding(get: { core.activationRequested }, set: core.setActive)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("ui.keepAwake"))
                    .font(.body.weight(.medium))
                Text(core.preparingActivation ? L10n.text("ui.preparing") : (core.applying ? L10n.text("ui.confirming") : (core.active ? elapsedLabel : L10n.text("ui.lidClosed"))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .disabled(core.installingHelper || core.preparingUpdate)
        .accessibilityLabel(L10n.text("ui.keepAwake"))
    }

    private var preferences: some View {
        VStack(spacing: 11) {
            Toggle(isOn: Binding(get: { core.agentsEnabled }, set: core.setAgentsEnabled)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("ui.agents"))
                    Text(L10n.text("ui.agentsDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel(L10n.text("ui.agents"))
            Text(L10n.text("ui.safety"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Toggle(isOn: Binding(
                get: { core.openAtLogin },
                set: core.setOpenAtLogin
            )) {
                Label(L10n.text("ui.login"), systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle(isOn: Binding(
                get: { core.activateOnLaunch },
                set: core.setActivateOnLaunch
            )) {
                Label(L10n.text("ui.startActive"), systemImage: "wand.and.sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.subheadline)
    }

    private var footer: some View {
        HStack {
            Button(L10n.text(updater.updateAvailable ? "ui.updateAvailable" : "ui.checkUpdates"),
                   systemImage: "arrow.triangle.2.circlepath", action: updater.checkForUpdates)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(updater.updateAvailable ? Color.accentColor : .secondary)
                .disabled(!updater.canPerformUpdateAction || core.installingHelper || core.repairingGuardian || core.preparingUpdate)
                .help(L10n.text("ui.updatesDescription"))
            Menu {
                Text(L10n.text("ui.updateVersion", updater.currentVersion))
                Text(L10n.text("ui.language", L10n.languageName))
                Toggle(L10n.text("ui.autoUpdates"), isOn: Binding(get: { updater.automaticallyInstalls }, set: updater.setAutomaticallyInstalls))
                    .disabled(core.preparingUpdate)
                Divider()
                Button(L10n.text("ui.community")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/reyhenrick/insonia")!)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(L10n.text("ui.more"))
            Spacer()
            Button(L10n.text("ui.quit"), systemImage: "power", action: onQuit)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(core.installingHelper || core.repairingGuardian)
        }
    }

    private var elapsedLabel: String {
        guard let since = core.activeSince else { return L10n.text("ui.active") }
        let seconds = max(0, Int(now.timeIntervalSince(since)))
        let duration: String
        if seconds < 60 {
            duration = L10n.text("ui.durationSeconds", String(seconds))
        } else {
            let minutes = seconds / 60
            if minutes < 60 {
                duration = L10n.text("ui.durationMinutes", String(minutes))
            } else {
                let hours = minutes / 60
                let rest = minutes % 60
                duration = rest == 0 ? L10n.text("ui.durationHours", String(hours))
                    : L10n.text("ui.durationHoursMinutes", String(hours), String(rest))
            }
        }
        return L10n.text("ui.activeFor", duration)
    }
}
