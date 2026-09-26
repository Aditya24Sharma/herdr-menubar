import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var monitor: HerdrMonitor
    @State private var showingSettings = false

    private static let panelWidth: CGFloat = 258
    private static let scrollThreshold = 6
    private static let maxListHeight: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar

            if showingSettings {
                SettingsPanel()
                Divider()
            }

            if !monitor.isConnected { disconnectedNotice }

            agentArea
        }
        .frame(width: Self.panelWidth)
    }

    // A ScrollView has no intrinsic height inside MenuBarExtra and collapses a
    // short list to nothing, so only long lists scroll, at a fixed height.
    @ViewBuilder
    private var agentArea: some View {
        if monitor.agents.isEmpty {
            if monitor.isConnected { emptyState }
        } else if monitor.agents.count > Self.scrollThreshold {
            // ThinScrollers must sit inside the content to find the NSScrollView
            // by walking up its superviews.
            ScrollView { agentList.background(ThinScrollers()) }
                .frame(height: Self.maxListHeight)
                .scrollIndicators(.never)
        } else {
            agentList
        }
    }

    private var agentList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(monitor.agentsByWorkspace, id: \.workspace.id) { group in
                WorkspaceSection(workspace: group.workspace, agents: group.agents)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

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

    private var topBar: some View {
        HStack(spacing: 9) {
            QuitButton()
            Spacer()
            settingsToggle
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 1)
    }

    private var settingsToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) { showingSettings.toggle() }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12))
                .foregroundStyle(showingSettings ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Settings")
        .pointerCursor()
    }
}
