import Foundation

/// `done` is Herdr's idle state for finished work not yet seen in its UI; the
/// menu bar exists to surface that difference, so it stays separate from `idle`.
enum AgentStatus: String {
    case working
    case blocked
    case done
    case idle
    case unknown

    init(raw: String?) {
        self = AgentStatus(rawValue: raw ?? "") ?? .unknown
    }

    var isResting: Bool { self == .idle || self == .unknown }
}
