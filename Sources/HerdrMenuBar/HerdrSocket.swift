import Foundation

/// Raw line-delimited JSON transport over Herdr's Unix domain socket.
///
/// Herdr speaks one JSON object per line in both directions. A request/response
/// call uses a short-lived connection; an event subscription keeps its
/// connection open and receives pushed lines until the server or client closes.
enum HerdrSocket {
    enum SocketError: Error, LocalizedError {
        case cannotCreate(String)
        case cannotConnect(String)
        case pathTooLong
        case closed
        case server(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreate(let detail): return "could not create socket: \(detail)"
            case .cannotConnect(let detail): return "could not reach the Herdr server: \(detail)"
            case .pathTooLong: return "socket path is too long for sockaddr_un"
            case .closed: return "connection closed"
            case .server(let message): return message
            }
        }
    }

    /// Resolves the server socket, preferring the path Herdr injected into our
    /// environment and falling back to the documented default location.
    static func defaultPath() -> String {
        if let injected = ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"],
           !injected.isEmpty {
            return injected
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/herdr/herdr.sock"
    }

    static func connect(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SocketError.cannotCreate(String(cString: strerror(errno)))
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(path.utf8)
        guard bytes.count < maxLen else {
            close(fd)
            throw SocketError.pathTooLong
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.baseAddress!.copyMemory(from: bytes, byteCount: bytes.count)
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let detail = String(cString: strerror(errno))
            close(fd)
            throw SocketError.cannotConnect(detail)
        }
        return fd
    }

    static func writeLine(_ fd: Int32, _ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written <= 0 { throw SocketError.closed }
                offset += written
            }
        }
    }

    /// Reads whole lines off a file descriptor, buffering partial reads.
    final class LineReader {
        enum Outcome {
            case line(Data)
            /// The receive timeout elapsed; the connection is still healthy.
            case timedOut
            case closed
        }

        private let fd: Int32
        private var buffer = Data()

        init(fd: Int32) { self.fd = fd }

        func next() -> Outcome {
            while true {
                if let range = buffer.firstRange(of: Data([0x0A])) {
                    let line = buffer[..<range.lowerBound]
                    buffer.removeSubrange(..<range.upperBound)
                    if line.isEmpty { continue }
                    return .line(Data(line))
                }
                var chunk = [UInt8](repeating: 0, count: 16384)
                let count = read(fd, &chunk, chunk.count)
                if count > 0 {
                    buffer.append(contentsOf: chunk[..<count])
                    continue
                }
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    return .timedOut
                }
                return .closed
            }
        }
    }

    /// Applies a receive timeout so a blocked read returns instead of hanging.
    static func setReceiveTimeout(_ fd: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Sends one request on a throwaway connection and returns the `result` object.
    @discardableResult
    static func request(
        method: String,
        params: [String: Any] = [:],
        path: String = defaultPath()
    ) throws -> [String: Any] {
        let fd = try connect(path: path)
        defer { close(fd) }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        try writeLine(fd, ["id": "menubar:\(method)", "method": method, "params": params])

        guard case .line(let line) = LineReader(fd: fd).next(),
              let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        else {
            throw SocketError.closed
        }
        if let error = object["error"] as? [String: Any] {
            throw SocketError.server(error["message"] as? String ?? "unknown server error")
        }
        return object["result"] as? [String: Any] ?? [:]
    }
}
