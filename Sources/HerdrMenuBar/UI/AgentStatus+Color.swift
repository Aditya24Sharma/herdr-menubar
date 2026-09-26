import SwiftUI

extension AgentStatus {
    var color: Color {
        switch self {
        case .working: return .accentColor
        case .blocked: return .red
        case .done: return .green
        case .idle, .unknown: return .secondary
        }
    }
}
