import SwiftUI

/// The dropdown panel: agents grouped by workspace, most urgent first.
struct MenuContent: View {
    @EnvironmentObject var monitor: HerdrMonitor
    @EnvironmentObject var settings: Settings
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !monitor.isConnected { disconnectedNotice }

            if monitor.agents.isEmpty {
                if monitor.isConnected { emptyState }
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
        VStack(alignment: .leading, spacing: 13) {
            ForEach(monitor.agentsByWorkspace, id: \.workspace.id) { group in
                WorkspaceSection(workspace: group.workspace, agents: group.agents)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// Only appears when Herdr is unreachable. Without it a dropped connection
    /// would look like a session where nothing happens to be running.
    private var disconnectedNotice: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text("Can't reach Herdr")
                    .font(.system(size: 12, weight: .medium))
                if let error = monitor.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        Text("No agents running.")
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
            .pointerCursor()
        }
    }
}

private struct WorkspaceSection: View {
    let workspace: Workspace
    let agents: [Agent]

    @Environment(\.colorScheme) private var scheme

    /// Recessed rather than raised, so the rows still read as the content and
    /// the section is only a boundary. Black in both themes, because tinting
    /// with the foreground colour would lighten the dark one instead.
    private var sectionFill: Color {
        Color.black.opacity(scheme == .dark ? 0.20 : 0.045)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(workspace.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(agents) { agent in
                    AgentRow(agent: agent)
                }
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(sectionFill)
            )
            .padding(.horizontal, 8)
        }
    }
}

private struct AgentRow: View {
    let agent: Agent

    /// Supported in newer macOS versions and inert in older ones, so
    /// `MenuPanel.close()` backs it up.
    @Environment(\.dismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        Button {
            // Dismiss first so the panel is gone before the terminal comes
            // forward, rather than lingering over it.
            dismiss()
            MenuPanel.close()
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
                    .fill(hovering ? Color.primary.opacity(0.10) : .clear)
            )
            // Inset within the section, not the panel.
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerCursor()
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

/// A hand cursor over anything clickable.
///
/// `push` and `pop` have to stay balanced, and the panel can close while the
/// pointer is still inside a row — the jump does exactly that — so the pop is
/// mirrored on disappear as well. Without it the cursor stays a hand over the
/// whole screen.
private struct PointerCursor: ViewModifier {
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != inside else { return }
                inside = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                guard inside else { return }
                inside = false
                NSCursor.pop()
            }
    }
}

private extension View {
    func pointerCursor() -> some View { modifier(PointerCursor()) }
}
