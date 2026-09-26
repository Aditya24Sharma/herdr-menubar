import Darwin

enum ProcessInspector {
    private static let argcSize = MemoryLayout<Int32>.size

    static func allPIDs() -> [pid_t] {
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

    static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    static func arguments(of pid: pid_t) -> [String] {
        guard let buffer = rawArguments(of: pid) else { return [] }
        return parseProcArgs(buffer)
    }

    private static func rawArguments(of pid: pid_t) -> [CChar]? {
        guard let argMax = maxArgumentsSize() else { return nil }
        var buffer = [CChar](repeating: 0, count: argMax)
        var bufferSize = argMax
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &bufferSize, nil, 0) == 0,
              bufferSize > argcSize
        else { return nil }
        return Array(buffer[..<bufferSize])
    }

    private static func maxArgumentsSize() -> Int? {
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return nil }
        return Int(argMax)
    }

    // KERN_PROCARGS2 layout: argc (Int32), exec path, NUL padding, then argc NUL-terminated args.
    private static func parseProcArgs(_ buffer: [CChar]) -> [String] {
        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { raw in
            buffer.withUnsafeBytes { source in
                raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: source[..<argcSize]))
            }
        }
        guard argc > 0 else { return [] }

        let bytes = buffer[argcSize...].map { UInt8(bitPattern: $0) }
        let chunks = bytes.split(separator: 0, omittingEmptySubsequences: true)
        return chunks.dropFirst().prefix(Int(argc)).map {
            String(decoding: $0, as: UTF8.self)
        }
    }
}
