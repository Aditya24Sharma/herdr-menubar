import Foundation

/// Diagnostics, off unless HERDR_MENUBAR_DEBUG is set in the environment.
///
/// Writes to stderr and to a log file, because the app is normally launched
/// through LaunchServices where stderr goes nowhere.
enum Log {
    private static let enabled =
        ProcessInfo.processInfo.environment["HERDR_MENUBAR_DEBUG"] != nil
    private static let lock = NSLock()
    private static let fileURL: URL = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        return logs.appendingPathComponent("HerdrMenuBar.log")
    }()

    static func debug(_ message: String) {
        guard enabled else { return }
        let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardError.write(Data(line.utf8))
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: fileURL)
        }
    }
}
