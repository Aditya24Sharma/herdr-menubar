import AppKit

// Herdr can only move focus inside itself; raising the terminal window is a macOS job.
// Walking the client's parent chain finds the exact hosting instance, unlike TERM_PROGRAM.
enum TerminalActivator {
    private static let herdrProcessName = "herdr"
    private static let serverArgument = "server"
    private static let maxAncestorHops = 16

    static func activateHostTerminal() {
        hostTerminal()?.activate(options: [.activateAllWindows])
    }

    static func hostTerminalBundleID() -> String? {
        hostTerminal()?.bundleIdentifier
    }

    private static func hostTerminal() -> NSRunningApplication? {
        guard let clientPID = herdrClientPIDs().first else { return nil }
        return guiAncestor(of: clientPID)
    }

    private static func herdrClientPIDs() -> [pid_t] {
        let clients = ProcessInspector.allPIDs().filter(isHerdrClient)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return clients.sorted { lhs, rhs in
            let lhsInFront = guiAncestor(of: lhs)?.processIdentifier == frontmost
            let rhsInFront = guiAncestor(of: rhs)?.processIdentifier == frontmost
            if lhsInFront != rhsInFront { return lhsInFront }
            return lhs < rhs
        }
    }

    private static func isHerdrClient(_ pid: pid_t) -> Bool {
        ProcessInspector.name(of: pid) == herdrProcessName
            && !ProcessInspector.arguments(of: pid).contains(serverArgument)
    }

    // Shells, `login` and the Herdr client have no bundle identifier, so the first
    // ancestor with one is the terminal emulator.
    private static func guiAncestor(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<maxAncestorHops {
            if let app = NSRunningApplication(processIdentifier: current),
               app.bundleIdentifier != nil {
                return app
            }
            guard let parent = ProcessInspector.parentPID(of: current),
                  parent > 1, parent != current
            else { return nil }
            current = parent
        }
        return nil
    }
}
