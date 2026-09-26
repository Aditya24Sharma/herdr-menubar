import Foundation

// Also writes to a file because LaunchServices discards the app's stderr.
enum Log {
    private static let debugEnvironmentVariable = "HERDR_MENUBAR_DEBUG"
    private static let errorPrefix = "herdr-menubar: "
    private static let isDebugEnabled =
        ProcessInfo.processInfo.environment[debugEnvironmentVariable] != nil
    private static let lock = NSLock()
    private static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs")
        .appendingPathComponent("HerdrMenuBar.log")

    static func error(_ message: String) {
        NSLog("%@", errorPrefix + message)
    }

    static func debug(_ message: String) {
        guard isDebugEnabled else { return }
        let line = Data("[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n".utf8)
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardError.write(line)
        appendToFile(line)
    }

    private static func appendToFile(_ data: Data) {
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }
}
