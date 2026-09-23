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
            } else if monitor.agents.count > Self.scrollThreshold {
                ScrollView { agentList }.frame(height: 340)
            } else {
                agentList
            }

            Divider()
            footer
        }
        .frame(width: 258)
    }

    /// Above this many agents the list scrolls instead of growing.
    private static let scrollThreshold = 8

    /// A ScrollView has no intrinsic height, and MenuBarExtra sizes its panel to
    /// fit its content, so wrapping a short list in one collapses it to nothing.
    /// Short lists are therefore laid out directly and only long ones scroll,
    /// with an explicit height.
    private var agentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(monitor.agentsByWorkspace, id: \.workspace.id) { group in
                WorkspaceSection(workspace: group.workspace, agents: group.agents)
            }
        }
        .padding(.vertical, 8)
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
        .padding(.horizontal, 16)
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
        .padding(.horizontal, 16)
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
                .padding(.horizontal, 16)
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
            .padding(.horizontal, 16)
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
                .padding(.horizontal, 16)
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
                StatusIndicator(status: agent.status)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let path = agent.displayPath {
                        Text(path)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 0)
            }
            // Idle agents want nothing, so they recede and let the active ones
            // carry the eye. Applied before the background so hover stays solid.
            .opacity(agent.status.isResting ? 0.5 : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
            // Inset so the hover highlight floats clear of the panel edges
            // instead of running into them.
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(agent.status.label) — click to jump to \(agent.paneID)")
    }
}

/// The leading mark on a row. A working agent gets a turning spinner, because
/// a still dot cannot say whether the agent is moving or wedged; every other
/// state is a plain dot.
private struct StatusIndicator: View {
    let status: AgentStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds per full turn.
    private static let period: TimeInterval = 0.9

    var body: some View {
        Group {
            if status == .working && !reduceMotion {
                // Driven from the clock, not `withAnimation`. A repeating
                // animation transaction leaks into the enclosing view, so every
                // republish of the agent list animated the whole panel.
                TimelineView(.animation) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: Self.period) / Self.period
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(status.color,
                                style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 9, height: 9)
                        .rotationEffect(.degrees(turn * 360))
                }
            } else {
                let size: CGFloat = status == .blocked ? 9 : 7
                Circle()
                    .fill(status.color)
                    .frame(width: size, height: size)
            }
        }
        // A fixed box so the spinner and the dot leave names on the same line.
        .frame(width: 10, height: 10)
    }
}
