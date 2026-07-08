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

    public func roundTrip(_ request: WireRequest) throws -> WireResponse {
        guard path.utf8.count < Self.maxSunPathBytes else {
            throw SocketClientError.pathTooLong(path)
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SocketClientError.connectFailed(errno: errno) }
        defer { close(descriptor) }
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
        try send(request, to: descriptor)
        return try receiveResponse(from: descriptor)
    }

    private func send(_ request: WireRequest, to descriptor: Int32) throws {
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
