import Foundation

@MainActor
struct NotificationPolicy {
    let settings: Settings
    let notifier: Notifier

    func announce(_ agent: Agent, from previous: AgentStatus, workspaceName: String?) {
        guard let title = title(for: agent, from: previous) else { return }
        Log.debug("notifying: \(agent.displayName) \(agent.status.rawValue)")
        notifier.notify(title: title, body: workspaceName ?? agent.displayPath ?? "",
                        paneID: agent.paneID, sound: settings.playSound)
    }

    private func title(for agent: Agent, from previous: AgentStatus) -> String? {
        switch agent.status {
        case .blocked where settings.notifyOnBlocked:
            return "\(agent.displayName) needs you"
        case .done where settings.notifyOnDone && previous == .working:
            return "\(agent.displayName) finished"
        default:
            return nil
        }
    }
}
