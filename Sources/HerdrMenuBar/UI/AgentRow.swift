import SwiftUI

struct AgentRow: View {
    let agent: Agent

    // Inert on older macOS versions, so `MenuPanel.close()` backs it up.
    @Environment(\.dismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        Button(action: jump) {
            label
                // Before the background, so the hover highlight stays solid.
                .opacity(agent.status.isResting ? 0.5 : 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? Color.primary.opacity(0.10) : .clear)
                )
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerCursor()
    }

    private var label: some View {
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
    }

    // Close the panel first so it is gone before the terminal comes forward.
    private func jump() {
        dismiss()
        MenuPanel.close()
        PaneNavigator.jump(to: agent.paneID)
    }
}
