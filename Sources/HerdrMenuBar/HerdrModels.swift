import SwiftUI

/// Lifecycle states Herdr reports for a pane occupant.
///
/// `done` is the same underlying idle state as `idle`, reported when work that
/// finished has not yet been seen in the focused Herdr UI. That distinction is
/// the whole point of the menu bar item, so the two are kept apart here.
enum AgentStatus: String, Codable {
    case working
    case blocked
    case done
    case idle
    case unknown

    init(raw: String?) {
        self = AgentStatus(rawValue: raw ?? "") ?? .unknown
    }

    var label: String {
        switch self {
        case .working: return "working"
        case .blocked: return "needs you"
        case .done: return "done"
        case .idle: return "idle"
        case .unknown: return "unknown"
        }
    }

    var color: Color {
        switch self {
        case .working: return .accentColor
        case .blocked: return .orange
        case .done: return .green
        case .idle, .unknown: return .secondary
        }
    }

    /// True when the agent is not doing anything and is not waiting on anyone.
    var isResting: Bool { self == .idle || self == .unknown }

    /// Ordering for the dropdown: the agents that want something come first.
    var sortRank: Int {
        switch self {
        case .blocked: return 0
        case .done: return 1
        case .working: return 2
        case .idle: return 3
        case .unknown: return 4
        }
    }
}

struct Agent: Identifiable, Equatable {
    let paneID: String
    let tabID: String
    let workspaceID: String
    var kind: String          // "claude", "codex", ...
    var name: String?         // set via `herdr agent rename`
    var status: AgentStatus
    var title: String?        // terminal title, stripped of spinner glyphs
    var cwd: String?

    var id: String { paneID }

    /// Best available human label, falling back until something is printable.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let title {
            let cleaned = Agent.strippingActivityGlyph(title)
            if !cleaned.isEmpty { return cleaned }
        }
        if !kind.isEmpty { return kind }
        return paneID
    }

    /// Glyphs an agent animates into its terminal title while it works.
    ///
    /// Herdr strips the set it knows (`src/terminal/title.rs`) but not the
    /// quadrant circles newer Claude Code versions cycle through, so those
    /// arrive in `terminal_title_stripped` and make the name flicker as they
    /// rotate. The rule here matches Herdr's: remove at most one leading glyph,
    /// and only when whitespace or the end of the string follows it, so a title
    /// that legitimately starts with one of these characters survives.
    private static let activityGlyphs: Set<Character> = [
        "\u{00B7}", "\u{2722}", "\u{2733}", "\u{2736}", "\u{273B}", "\u{273D}",
        "\u{25D0}", "\u{25D1}", "\u{25D2}", "\u{25D3}",
    ]

    static func strippingActivityGlyph(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return trimmed }

        let isBraille = first.unicodeScalars.first
            .map { (0x2800...0x28FF).contains(Int($0.value)) } ?? false
        guard isBraille || activityGlyphs.contains(first) else { return trimmed }

        let rest = trimmed.dropFirst()
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return trimmed }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// Trailing context line: the directory the agent is working in.
    var displayPath: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).abbreviatingWithTildeInPath
    }
}

struct Workspace: Identifiable, Equatable {
    let workspaceID: String
    var label: String?
    var number: Int?

    var id: String { workspaceID }

    var displayName: String {
        if let label, !label.isEmpty { return label }
        if let number { return "workspace \(number)" }
        return workspaceID
    }
}

/// Decoding helpers for the loosely-typed JSON the socket returns.
extension Agent {
    init?(json: [String: Any]) {
        guard let paneID = json["pane_id"] as? String else { return nil }
        self.paneID = paneID
        self.tabID = json["tab_id"] as? String ?? ""
        self.workspaceID = json["workspace_id"] as? String ?? ""
        self.kind = json["agent"] as? String ?? ""
        self.name = json["name"] as? String
        self.status = AgentStatus(raw: json["agent_status"] as? String)
        self.title = (json["terminal_title_stripped"] as? String)
            ?? (json["terminal_title"] as? String)
        self.cwd = (json["foreground_cwd"] as? String) ?? (json["cwd"] as? String)
    }
}

extension Workspace {
    init?(json: [String: Any]) {
        guard let workspaceID = json["workspace_id"] as? String else { return nil }
        self.workspaceID = workspaceID
        self.label = json["label"] as? String
        self.number = json["number"] as? Int
    }
}
