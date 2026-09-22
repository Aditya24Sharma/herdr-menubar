import AppKit
import Foundation

/// Moves the user to a pane.
///
/// This is two separate jobs. `pane.focus` moves focus *inside* Herdr, which is
/// all the server can do. Bringing the terminal window to the front is a macOS
/// job, and Herdr cannot help: the menu bar app is a different process, so it
/// cannot read the client's `TERM_PROGRAM` the way Herdr's own notifier does.
/// Walking the client's parent chain is more robust anyway, since it identifies
/// the exact running instance rather than a bundle ID.
enum Jumper {
    static func jump(to paneID: String) {
        do {
            try HerdrSocket.request(method: "pane.focus", params: ["pane_id": paneID])
        } catch {
            NSLog("herdr-menubar: pane.focus failed: \(error.localizedDescription)")
        }
        activateHostTerminal()
    }

    /// Bundle identifier of the terminal hosting a Herdr client, if any.
    /// Used to tell `terminal-notifier` which app to raise on click.
    static func hostTerminalBundleID() -> String? {
        guard let clientPID = herdrClientPIDs().first else { return nil }
        return guiAncestor(of: clientPID)?.bundleIdentifier
    }

    /// Absolute path of an executable on the usual paths, for spawning tools
    /// from a GUI app, whose PATH does not include Homebrew.
    static func locate(_ program: String) -> String? {
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for directory in candidates {
            let path = "\(directory)/\(program)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Brings whichever GUI app is hosting a Herdr client to the front.
    static func activateHostTerminal() {
        guard let clientPID = herdrClientPIDs().first,
              let app = guiAncestor(of: clientPID)
        else { return }
        app.activate(options: [.activateAllWindows])
    }

    // MARK: - Process discovery

    /// Every running `herdr` process that is a client rather than the server.
    private static func herdrClientPIDs() -> [pid_t] {
        var candidates: [pid_t] = []
        for pid in allPIDs() {
            guard processName(pid) == "herdr" else { continue }
            let args = processArguments(pid)
            // `herdr server` is the background daemon, not an attached client.
            if args.contains("server") { continue }
            candidates.append(pid)
        }
        // Prefer a client whose host app is already frontmost, so that jumping
        // with several terminals open stays in the one the user last used.
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return candidates.sorted { lhs, rhs in
            let l = guiAncestor(of: lhs)?.processIdentifier == frontmost
            let r = guiAncestor(of: rhs)?.processIdentifier == frontmost
            if l != r { return l }
            return lhs < rhs
        }
    }

    /// Walks up the process tree until it hits something with a bundle
    /// identifier. Shells, `login` and the Herdr client itself have none, so the
    /// first match is the terminal emulator.
    private static func guiAncestor(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<16 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.bundleIdentifier != nil {
                return app
            }
            guard let parent = parentPID(of: current), parent > 1, parent != current else {
                return nil
            }
            current = parent
        }
        return nil
    }

    private static func allPIDs() -> [pid_t] {
        var size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return [] }
        let capacity = Int(size) / MemoryLayout<pid_t>.size + 16
        var pids = [pid_t](repeating: 0, count: capacity)
        size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids,
                             Int32(capacity * MemoryLayout<pid_t>.size))
        guard size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<pid_t>.size
        return Array(pids[..<count]).filter { $0 > 0 }
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN) + 1)
        let rc = proc_name(pid, &buffer, UInt32(buffer.count))
        guard rc > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    /// Reads a process's argv via KERN_PROCARGS2 to tell `herdr` from `herdr server`.
    private static func processArguments(_ pid: pid_t) -> [String] {
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: Int(argMax))
        var bufferSize = Int(argMax)
        var argsMIB: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&argsMIB, 3, &buffer, &bufferSize, nil, 0) == 0,
              bufferSize > MemoryLayout<Int32>.size
        else { return [] }

        // Layout: argc (Int32), exec path, NUL padding, then argc NUL-terminated args.
        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { raw in
            buffer.withUnsafeBytes { source in
                raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: source[..<4]))
            }
        }
        guard argc > 0 else { return [] }

        let bytes = buffer[MemoryLayout<Int32>.size..<bufferSize].map { UInt8(bitPattern: $0) }
        let chunks = bytes.split(separator: 0, omittingEmptySubsequences: true)
        // Drop the exec path, keep argv[0...]; argv[1...] is what we test.
        return chunks.dropFirst().prefix(Int(argc)).map {
            String(decoding: $0, as: UTF8.self)
        }
    }
}
