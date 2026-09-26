import SwiftUI

struct WorkspaceSection: View {
    let workspace: Workspace
    let agents: [Agent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
            VStack(alignment: .leading, spacing: 2) {
                ForEach(agents) { agent in
                    AgentRow(agent: agent)
                }
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 9) {
            Text(workspace.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
    }
}
