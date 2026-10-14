import Combine
import SwiftUI

struct StatusIcon: View {
    @ObservedObject var core: PowerCore

    var body: some View {
        Image(systemName: core.active ? "bolt.fill" : "bolt.slash")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: core.active)
            .frame(width: 22, height: 22)
    }
}

struct PanelView: View {
    static let cornerRadius: CGFloat = 22

    @ObservedObject var core: PowerCore
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
            if core.helperNeeded {
                Button(core.installingHelper ? L10n.text("ui.authorizing") : L10n.text(core.protectionInstalled ? "ui.updateProtection" : "ui.installProtection"),
                       action: core.installHelper)
                    .disabled(core.installingHelper || core.repairingGuardian)
                    .controlSize(.regular)
                Text(L10n.text("ui.authorizationHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !core.guardianReady && !core.active && !core.applying {
                Button(core.repairingGuardian ? L10n.text("ui.repairing") : L10n.text("ui.repair"), action: core.repairGuardian)
                    .disabled(core.repairingGuardian || core.installingHelper)
                    .font(.caption)
            }
            footer
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
            Image(systemName: core.guardianReady && !core.helperNeeded ? "checkmark.shield" : "shield.lefthalf.filled")
                .foregroundStyle(core.guardianReady && !core.helperNeeded ? .green : .secondary)
                .help(L10n.text(core.guardianReady && !core.helperNeeded ? "ui.protectionReady" : "ui.protectionAttention"))
                .accessibilityLabel(L10n.text(core.guardianReady && !core.helperNeeded ? "ui.protectionReady" : "ui.protectionAttention"))
        }
    }

    private var mainControl: some View {
        Toggle(isOn: Binding(get: { core.active || core.applying }, set: core.setActive)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("ui.keepAwake"))
                    .font(.body.weight(.medium))
                Text(core.applying ? L10n.text("ui.confirming") : (core.active ? elapsedLabel : L10n.text("ui.lidClosed")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .disabled(core.installingHelper || core.repairingGuardian)
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
            Button(L10n.text("ui.help"), systemImage: "questionmark.circle", action: core.openHelp)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Text(L10n.text("ui.language", L10n.languageName))
                Button(L10n.text("ui.community")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/reyhenrick/insonia")!)
                }
                Divider()
                Button(L10n.text("ui.removeProtection"), action: core.removeProtection)
                    .disabled(core.installingHelper || core.repairingGuardian)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(L10n.text("ui.community"))
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
