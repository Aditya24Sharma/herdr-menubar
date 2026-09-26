import Foundation

struct Agent: Identifiable, Equatable {
    let paneID: String
    let workspaceID: String
    var kind: String
    var name: String?
    var status: AgentStatus
    var title: String?
    var cwd: String?

    var id: String { paneID }

    /// Parsed from a `w3Y:p12` style id so p2 sorts before p10.
    var paneNumber: Int? {
        guard let marker = paneID.range(of: ":p") else { return nil }
        return Int(paneID[marker.upperBound...])
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let title {
            let cleaned = ActivityGlyph.stripLeading(from: title)
            if !cleaned.isEmpty { return cleaned }
        }
        if !kind.isEmpty { return kind }
        return paneID
    }

    var displayPath: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).abbreviatingWithTildeInPath
    }
}
