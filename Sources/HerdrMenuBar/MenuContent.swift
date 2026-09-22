import SwiftUI

/// The dropdown panel: agents grouped by workspace, most urgent first.
struct MenuContent: View {
    @EnvironmentObject var monitor: HerdrMonitor
    @EnvironmentObject var settings: Settings
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if monitor.agents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(monitor.agentsByWorkspace, id: \.workspace.id) { group in
                            WorkspaceSection(workspace: group.workspace, agents: group.agents)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 360)
            }

            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Agents")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Circle()
                .fill(monitor.isConnected ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(monitor.isConnected ? summary : "disconnected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var summary: String {
        var parts: [String] = []
        if monitor.blockedCount > 0 { parts.append("\(monitor.blockedCount) waiting") }
        if monitor.workingCount > 0 { parts.append("\(monitor.workingCount) working") }
        if monitor.doneCount > 0 { parts.append("\(monitor.doneCount) done") }
        return parts.isEmpty ? "all idle" : parts.joined(separator: ", ")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(monitor.isConnected ? "No agents running." : "Can't reach Herdr.")
                .font(.system(size: 12))
            if let error = monitor.lastError, !monitor.isConnected {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showingSettings {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Notify when an agent needs me", isOn: $settings.notifyOnBlocked)
                    Toggle("Notify when an agent finishes", isOn: $settings.notifyOnDone)
                    Toggle("Play a sound", isOn: $settings.playSound)
                    Toggle("Launch at login", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.launchAtLogin = $0 }))
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
            }
            HStack {
                Button(showingSettings ? "Hide settings" : "Settings") {
                    withAnimation(.easeInOut(duration: 0.12)) { showingSettings.toggle() }
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct WorkspaceSection: View {
    let workspace: Workspace
    let agents: [Agent]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workspace.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            ForEach(agents) { agent in
                AgentRow(agent: agent)
            }
        }
    }
}

private struct AgentRow: View {
    let agent: Agent
    @State private var hovering = false

    var body: some View {
        Button {
            Jumper.jump(to: agent.paneID)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(agent.status.color)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let path = agent.displayPath {
                        Text(path)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 6)
                Text(agent.status.label)
                    .font(.system(size: 10))
                    .foregroundStyle(agent.status == .blocked ? agent.status.color : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Jump to \(agent.paneID)")
    }
}
