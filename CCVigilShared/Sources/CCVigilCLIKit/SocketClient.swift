import CCVigilShared
import Darwin
import Foundation

public enum SocketClientError: Error, Equatable, CustomStringConvertible {
    case pathTooLong(String)
    case connectFailed(errno: Int32)
    case sendFailed(errno: Int32)
    case receiveFailed(errno: Int32)
    case connectionClosed
    case replyTimedOut(afterSeconds: Int)
    case malformedReply(String)

    public var description: String {
        switch self {
        case let .pathTooLong(path):
            "socket path too long for sun_path: \(path)"
        case let .connectFailed(number):
            "cannot connect to the daemon socket (errno \(number)); is CCVigilDaemon running?"
        case let .sendFailed(number):
            "send to the daemon failed (errno \(number))"
        case let .receiveFailed(number):
            "receive from the daemon failed (errno \(number))"
        case .connectionClosed:
            "the daemon closed the connection before replying"
        case let .replyTimedOut(afterSeconds):
            "no reply from the daemon within \(afterSeconds)s; the operation may still have applied"
        case let .malformedReply(detail):
            "malformed reply from the daemon: \(detail)"
        }
    }
}

public struct SocketClient: Sendable {
    public static let defaultTimeoutSeconds = 5
    public static let maxSunPathBytes = 104

    public let path: String
    public let timeoutSeconds: Int

    public init(path: String, timeoutSeconds: Int = SocketClient.defaultTimeoutSeconds) {
        self.path = path
        self.timeoutSeconds = timeoutSeconds
    }

    /// The clear round-trip must outlast the daemon's worst-case confirm loop, so
    /// a slow-but-progressing pmset clear is never abandoned before it settles;
    /// every other op keeps the short default budget.
    public static func timeout(for request: WireRequest) -> Int {
        switch request {
        case .clear: ClearBudget.clientSeconds
        default: defaultTimeoutSeconds
        }
    }

    public func roundTrip(_ request: WireRequest) throws -> WireResponse {
        try withConnection { descriptor in
            try writeFrame(request, to: descriptor)
            return try receiveResponse(from: descriptor)
        }
    }

    /// Fire-and-forget: connect, write the frame, and return without awaiting a
    /// reply. The nudge hook path uses this so a slow or wedged daemon cannot
    /// block a PreToolUse hook — which stalls the tool it precedes — for the full
    /// reply timeout. The daemon still reads and applies the buffered frame.
    public func send(_ request: WireRequest) throws {
        try withConnection { descriptor in
            try writeFrame(request, to: descriptor)
        }
    }

    private func withConnection<T>(_ body: (Int32) throws -> T) throws -> T {
        guard path.utf8.count < Self.maxSunPathBytes else {
            throw SocketClientError.pathTooLong(path)
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SocketClientError.connectFailed(errno: errno) }
        defer { close(descriptor) }
        // A write to a daemon that closed its end must surface EPIPE through
        // sendFailed, never raise SIGPIPE and kill the CLI or its host process.
        var noSigPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { sunPath in
            sunPath.copyBytes(from: pathBytes)
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw SocketClientError.connectFailed(errno: errno) }
        return try body(descriptor)
    }

    private func writeFrame(_ request: WireRequest, to descriptor: Int32) throws {
        let frame = try WireCodec.encodeFrame(request)
        try frame.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(descriptor, base + offset, raw.count - offset)
                guard written > 0 else { throw SocketClientError.sendFailed(errno: errno) }
                offset += written
            }
        }
    }

    private func receiveResponse(from descriptor: Int32) throws -> WireResponse {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while buffer.count <= WireFrame.maxPayloadBytes + WireFrame.headerBytes {
            do {
                if let (response, _) = try WireCodec.decodeFrame(WireResponse.self, from: buffer) {
                    return response
                }
            } catch {
                throw SocketClientError.malformedReply(String(describing: error))
            }
            let received = recv(descriptor, &chunk, chunk.count, 0)
            if received > 0 {
                buffer.append(contentsOf: chunk[0 ..< received])
            } else if received == 0 {
                throw SocketClientError.connectionClosed
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                throw SocketClientError.replyTimedOut(afterSeconds: timeoutSeconds)
            } else {
                throw SocketClientError.receiveFailed(errno: errno)
            }
        }
        throw SocketClientError.malformedReply("reply exceeds the frame cap")
    }
}
