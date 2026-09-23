import Foundation
import SwiftUI

/// Owns the live view of every agent Herdr knows about.
///
/// Two quirks of Herdr's event API shape this design:
///
/// 1. `pane.agent_status_changed` is scoped to a single pane, so covering a
///    whole session means one subscription per pane, rebuilt when panes change.
/// 2. Lifecycle subscriptions (`pane.created` and friends) replay the server's
///    whole retained event buffer on subscribe, so a client cannot treat their
///    arrival as news. Reacting to them would mean resync, re-subscribe, replay,
///    forever.
///
/// So status arrives by push (those subscriptions start at the current sequence
/// and do not replay), while the *set* of panes is reconciled on a slow timer.
/// Status changes, the thing notifications depend on, are still instant.
@MainActor
final class HerdrMonitor: ObservableObject {
    @Published private(set) var agents: [Agent] = []
    @Published private(set) var workspaces: [String: Workspace] = [:]
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?

    private var monitorThread: Thread?
    private let stopFlag = AtomicFlag()
    private let settings: Settings
    private let notifier: Notifier

    /// How often to re-check which panes exist.
    nonisolated private static let reconcileInterval: TimeInterval = 5
    /// How long a read waits before yielding to the reconcile check.
    nonisolated private static let readTimeoutSeconds = 2

    init(settings: Settings, notifier: Notifier) {
        self.settings = settings
        self.notifier = notifier
    }

    /// Seeds state without connecting, so the panel can be rendered offscreen
    /// and inspected without a running Herdr server.
    init(settings: Settings, notifier: Notifier,
         agents: [Agent], workspaces: [Workspace], connected: Bool = true) {
        self.settings = settings
        self.notifier = notifier
        self.agents = agents.sorted(by: Self.ordering)
        self.workspaces = Dictionary(
            uniqueKeysWithValues: workspaces.map { ($0.workspaceID, $0) })
        self.isConnected = connected
    }

    func start() {
        guard monitorThread == nil else { return }
        let thread = Thread { [weak self] in self?.runLoop() }
        thread.name = "herdr.monitor"
        thread.stackSize = 512 * 1024
        monitorThread = thread
        thread.start()
    }

    func stop() { stopFlag.set(true) }

    // MARK: - Background connection loop

    nonisolated private func runLoop() {
        var backoff: UInt32 = 1
        while !stopFlag.value {
            do {
                try connectAndStream()
                backoff = 1
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                Log.debug("connection ended: \(message)")
                Task { @MainActor [weak self] in
                    self?.isConnected = false
                    self?.lastError = message
                }
                sleep(backoff)
                backoff = min(backoff * 2, 15)
            }
        }
    }

    /// Snapshots, subscribes, then streams until the pane set changes or the
    /// connection drops. Returning normally means "rebuild the subscription".
    nonisolated private func connectAndStream() throws {
        let path = HerdrSocket.defaultPath()
        var paneIDs = try resync(path: path)

        let fd = try HerdrSocket.connect(path: path)
        defer { close(fd) }
        HerdrSocket.setReceiveTimeout(fd, seconds: Self.readTimeoutSeconds)

        // Only agent status is subscribed. `pane.updated` would also carry
        // titles, but it fires ~10x a second while agents work (terminal titles
        // churn), and the reconcile below already refreshes that detail.
        var subscriptions: [[String: Any]] = []
        for paneID in paneIDs {
            subscriptions.append(["type": "pane.agent_status_changed", "pane_id": paneID])
        }

        try HerdrSocket.writeLine(fd, [
            "id": "menubar:subscribe",
            "method": "events.subscribe",
            "params": ["subscriptions": subscriptions],
        ])

        let reader = HerdrSocket.LineReader(fd: fd)
        guard case .line(let ack) = reader.next(),
              let ackObject = try JSONSerialization.jsonObject(with: ack) as? [String: Any]
        else { throw HerdrSocket.SocketError.closed }
        if let error = ackObject["error"] as? [String: Any] {
            throw HerdrSocket.SocketError.server(
                error["message"] as? String ?? "subscription refused")
        }

        Log.debug("subscribed over \(paneIDs.count) panes")
        Task { @MainActor [weak self] in
            self?.isConnected = true
            self?.lastError = nil
        }

        var lastReconcile = Date()
        while !stopFlag.value {
            switch reader.next() {
            case .line(let line):
                if let object = try? JSONSerialization.jsonObject(with: line)
                    as? [String: Any],
                   let event = object["event"] as? String {
                    handle(event: event, data: object["data"] as? [String: Any] ?? [:])
                }

            case .timedOut:
                break

            case .closed:
                Log.debug("stream closed by peer")
                throw HerdrSocket.SocketError.closed
            }

            // Checked every iteration rather than only on a read timeout, so a
            // busy stream cannot starve it.
            guard Date().timeIntervalSince(lastReconcile) >= Self.reconcileInterval
            else { continue }
            lastReconcile = Date()
            let current = try resync(path: path)
            if Set(current) != Set(paneIDs) {
                Log.debug("pane set changed (\(paneIDs.count) -> \(current.count)); resubscribing")
                paneIDs = current
                return
            }
        }
    }

    // MARK: - State application

    /// Pulls a fresh snapshot, publishes it, and returns the current pane IDs.
    nonisolated private func resync(path: String) throws -> [String] {
        let response = try HerdrSocket.request(method: "session.snapshot", path: path)
        guard let snapshot = response["snapshot"] as? [String: Any] else {
            throw HerdrSocket.SocketError.server("snapshot missing from response")
        }

        let agents = (snapshot["agents"] as? [[String: Any]] ?? [])
            .compactMap(Agent.init(json:))
        var workspaces: [String: Workspace] = [:]
        for object in snapshot["workspaces"] as? [[String: Any]] ?? [] {
            if let workspace = Workspace(json: object) {
                workspaces[workspace.workspaceID] = workspace
            }
        }
        let paneIDs = (snapshot["panes"] as? [[String: Any]] ?? [])
            .compactMap { $0["pane_id"] as? String }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.workspaces != workspaces { self.workspaces = workspaces }
            self.replaceAgents(agents)
        }
        return paneIDs
    }

    nonisolated private func handle(event: String, data: [String: Any]) {
        // Herdr spells these two ways: lifecycle events arrive as
        // `pane_updated`, while subscription-generated ones arrive as
        // `pane.agent_status_changed`. Normalise before matching.
        switch event.replacingOccurrences(of: ".", with: "_") {
        case "pane_agent_status_changed":
            guard let paneID = data["pane_id"] as? String else { return }
            let status = AgentStatus(raw: data["agent_status"] as? String)
            let title = data["title"] as? String
            let displayAgent = data["display_agent"] as? String
            Task { @MainActor [weak self] in
                self?.updateStatus(paneID: paneID, status: status,
                                   title: title, displayAgent: displayAgent)
            }
        default:
            break
        }
    }

    @MainActor
    private func replaceAgents(_ incoming: [Agent]) {
        let sorted = incoming.sorted(by: Self.ordering)
        // Republishing an identical list still rebuilds the panel, and a rebuild
        // restarts whatever is animating inside it. The reconcile runs every few
        // seconds, so without this guard the dropdown never settles.
        guard sorted != agents else { return }

        let previous = Dictionary(uniqueKeysWithValues: agents.map { ($0.paneID, $0.status) })
        agents = sorted
        Log.debug("agent list changed (\(sorted.count) agents)")
        // A reconcile can reveal a transition no push event covered.
        for agent in agents where agent.status == .blocked {
            if let was = previous[agent.paneID], was != .blocked { announce(agent, from: was) }
        }
    }

    @MainActor
    private func updateStatus(paneID: String, status: AgentStatus,
                              title: String?, displayAgent: String?) {
        guard let index = agents.firstIndex(where: { $0.paneID == paneID }) else { return }
        let previous = agents[index].status
        guard status != previous else { return }
        Log.debug("status \(paneID): \(previous.rawValue) -> \(status.rawValue)")
        agents[index].status = status
        if let title, !title.isEmpty { agents[index].title = title }
        if let displayAgent, !displayAgent.isEmpty { agents[index].kind = displayAgent }
        announce(agents[index], from: previous)
        agents.sort(by: Self.ordering)
    }

    /// Fires a desktop notification for transitions the user opted into.
    @MainActor
    private func announce(_ agent: Agent, from previous: AgentStatus) {
        let context = workspaces[agent.workspaceID]?.displayName
            ?? agent.displayPath ?? ""
        switch agent.status {
        case .blocked where settings.notifyOnBlocked:
            Log.debug("notifying: \(agent.displayName) blocked")
            notifier.notify(title: "\(agent.displayName) needs you", body: context,
                            paneID: agent.paneID, sound: settings.playSound)
        case .done where settings.notifyOnDone && previous == .working:
            Log.debug("notifying: \(agent.displayName) done")
            notifier.notify(title: "\(agent.displayName) finished", body: context,
                            paneID: agent.paneID, sound: settings.playSound)
        default:
            break
        }
    }

    private static func ordering(_ a: Agent, _ b: Agent) -> Bool {
        if a.status.sortRank != b.status.sortRank {
            return a.status.sortRank < b.status.sortRank
        }
        return a.paneID < b.paneID
    }

    // MARK: - Derived menu bar state

    var blockedCount: Int { agents.filter { $0.status == .blocked }.count }
    var doneCount: Int { agents.filter { $0.status == .done }.count }
    var workingCount: Int { agents.filter { $0.status == .working }.count }

    /// Highest-urgency status present, which drives icon colour and the count.
    var summaryStatus: AgentStatus {
        if blockedCount > 0 { return .blocked }
        if doneCount > 0 { return .done }
        if workingCount > 0 { return .working }
        return .idle
    }

    var agentsByWorkspace: [(workspace: Workspace, agents: [Agent])] {
        Dictionary(grouping: agents, by: \.workspaceID)
            .map { id, agents in
                (workspaces[id] ?? Workspace(workspaceID: id, label: nil, number: nil),
                 agents.sorted(by: Self.ordering))
            }
            .sorted { lhs, rhs in
                let l = lhs.agents.first?.status.sortRank ?? 9
                let r = rhs.agents.first?.status.sortRank ?? 9
                if l != r { return l < r }
                return lhs.workspace.displayName < rhs.workspace.displayName
            }
    }
}

/// A boolean that the UI thread sets and the monitor thread reads.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ newValue: Bool) {
        lock.lock()
        storage = newValue
        lock.unlock()
    }
}
