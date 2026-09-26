import Foundation

enum UnixSocketError: Error, LocalizedError {
    case cannotCreate(String)
    case cannotConnect(String)
    case pathTooLong
    case closed

    var errorDescription: String? {
        switch self {
        case .cannotCreate(let detail): return "could not create socket: \(detail)"
        case .cannotConnect(let detail): return "could not reach the Herdr server: \(detail)"
        case .pathTooLong: return "socket path is too long for sockaddr_un"
        case .closed: return "connection closed"
        }
    }
}

/// A newline-delimited connection to a Unix domain socket, closed on deinit.
final class UnixSocket {
    enum ReadOutcome {
        case line(Data)
        case timedOut
        case closed
    }

    private static let newline: UInt8 = 0x0A
    private static let readChunkSize = 16384

    private let fd: Int32
    private var buffer = Data()

    init(path: String) throws {
        fd = try Self.connect(path: path)
    }

    deinit { close(fd) }

    func setReceiveTimeout(seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    func writeLine(_ payload: Data) throws {
        var data = payload
        data.append(Self.newline)
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written <= 0 { throw UnixSocketError.closed }
                offset += written
            }
        }
    }

    func readLine() -> ReadOutcome {
        while true {
            if let line = takeBufferedLine() {
                if line.isEmpty { continue }
                return .line(line)
            }
            var chunk = [UInt8](repeating: 0, count: Self.readChunkSize)
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

    private func takeBufferedLine() -> Data? {
        guard let range = buffer.firstRange(of: Data([Self.newline])) else { return nil }
        let line = Data(buffer[..<range.lowerBound])
        buffer.removeSubrange(..<range.upperBound)
        return line
    }

    private static func connect(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixSocketError.cannotCreate(String(cString: strerror(errno)))
        }
        do {
            var address = try makeAddress(path: path)
            let rc = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard rc == 0 else {
                throw UnixSocketError.cannotConnect(String(cString: strerror(errno)))
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    private static func makeAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let bytes = Array(path.utf8)
        guard bytes.count < maxLength else { throw UnixSocketError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.baseAddress!.copyMemory(from: bytes, byteCount: bytes.count)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
}
