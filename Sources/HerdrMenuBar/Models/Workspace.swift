import Foundation

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
