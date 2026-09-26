import Foundation

enum HerdrClientError: Error, LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }
}

struct StatusChange {
    let paneID: String
    let status: AgentStatus
    let title: String?
    let displayAgent: String?
}

private typealias JSONObject = [String: Any]

struct HerdrClient {
    private static let requestTimeoutSeconds = 5
    private static let eventReadTimeoutSeconds = 2
    private static let requestIDPrefix = "menubar:"

    private let socketPath: String

    init(socketPath: String = HerdrClient.defaultSocketPath()) {
        self.socketPath = socketPath
    }

    static func defaultSocketPath() -> String {
        if let injected = ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"],
           !injected.isEmpty {
            return injected
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/herdr/herdr.sock"
    }

    func snapshot() throws -> Snapshot {
        let result = try request(method: "session.snapshot")
        guard let snapshot = result["snapshot"] as? JSONObject else {
            throw HerdrClientError.server("snapshot missing from response")
        }
        return Self.decodeSnapshot(snapshot)
    }

    func focus(paneID: String) throws {
        try request(method: "pane.focus", params: ["pane_id": paneID])
    }

    /// Subscribes per pane because `pane.agent_status_changed` is pane-scoped. `pane.updated`
    /// is avoided: it fires ~10x a second while agents work, as terminal titles animate.
    func subscribeToStatusChanges(of paneIDs: [String]) throws -> StatusEventStream {
        let socket = try UnixSocket(path: socketPath)
        socket.setReceiveTimeout(seconds: Self.eventReadTimeoutSeconds)

        let subscriptions = paneIDs.map { ["type": "pane.agent_status_changed", "pane_id": $0] }
        try send(method: "events.subscribe", params: ["subscriptions": subscriptions],
                 id: "subscribe", over: socket)
        try Self.readResponse(from: socket, fallbackError: "subscription refused")
        return StatusEventStream(socket: socket)
    }

    @discardableResult
    private func request(method: String, params: JSONObject = [:]) throws -> JSONObject {
        let socket = try UnixSocket(path: socketPath)
        socket.setReceiveTimeout(seconds: Self.requestTimeoutSeconds)
        try send(method: method, params: params, id: method, over: socket)
        let response = try Self.readResponse(from: socket, fallbackError: "unknown server error")
        return response["result"] as? JSONObject ?? [:]
    }

    private func send(method: String, params: JSONObject, id: String,
                      over socket: UnixSocket) throws {
        let message: JSONObject = [
            "id": Self.requestIDPrefix + id,
            "method": method,
            "params": params,
        ]
        try socket.writeLine(JSONSerialization.data(withJSONObject: message))
    }

    @discardableResult
    private static func readResponse(from socket: UnixSocket,
                                     fallbackError: String) throws -> JSONObject {
        guard case .line(let line) = socket.readLine(),
              let response = try JSONSerialization.jsonObject(with: line) as? JSONObject
        else {
            throw UnixSocketError.closed
        }
        if let error = response["error"] as? JSONObject {
            throw HerdrClientError.server(error["message"] as? String ?? fallbackError)
        }
        return response
    }

    private static func decodeSnapshot(_ json: JSONObject) -> Snapshot {
        Snapshot(
            agents: (json["agents"] as? [JSONObject] ?? []).compactMap(decodeAgent),
            workspaces: (json["workspaces"] as? [JSONObject] ?? []).compactMap(decodeWorkspace),
            paneIDs: (json["panes"] as? [JSONObject] ?? []).compactMap { $0["pane_id"] as? String }
        )
    }

    private static func decodeAgent(_ json: JSONObject) -> Agent? {
        guard let paneID = json["pane_id"] as? String else { return nil }
        return Agent(
            paneID: paneID,
            workspaceID: json["workspace_id"] as? String ?? "",
            kind: json["agent"] as? String ?? "",
            name: json["name"] as? String,
            status: AgentStatus(raw: json["agent_status"] as? String),
            title: (json["terminal_title_stripped"] as? String) ?? (json["terminal_title"] as? String),
            cwd: (json["foreground_cwd"] as? String) ?? (json["cwd"] as? String)
        )
    }

    private static func decodeWorkspace(_ json: JSONObject) -> Workspace? {
        guard let workspaceID = json["workspace_id"] as? String else { return nil }
        return Workspace(
            workspaceID: workspaceID,
            label: json["label"] as? String,
            number: json["number"] as? Int
        )
    }
}

final class StatusEventStream {
    enum Outcome {
        case statusChange(StatusChange)
        case timedOut
        case ignored
    }

    private let socket: UnixSocket

    fileprivate init(socket: UnixSocket) {
        self.socket = socket
    }

    func next() throws -> Outcome {
        switch socket.readLine() {
        case .line(let line):
            return Self.decodeEvent(line).map(Outcome.statusChange) ?? .ignored
        case .timedOut:
            return .timedOut
        case .closed:
            Log.debug("stream closed by peer")
            throw UnixSocketError.closed
        }
    }

    private static func decodeEvent(_ line: Data) -> StatusChange? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? JSONObject,
              let event = object["event"] as? String,
              isStatusChange(event)
        else { return nil }
        let data = object["data"] as? JSONObject ?? [:]
        guard let paneID = data["pane_id"] as? String else { return nil }
        return StatusChange(
            paneID: paneID,
            status: AgentStatus(raw: data["agent_status"] as? String),
            title: data["title"] as? String,
            displayAgent: data["display_agent"] as? String
        )
    }

    /// Herdr spells event names two ways (`pane_updated` vs `pane.agent_status_changed`).
    private static func isStatusChange(_ event: String) -> Bool {
        event.replacingOccurrences(of: ".", with: "_") == "pane_agent_status_changed"
    }
}
