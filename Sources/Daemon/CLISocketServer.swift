import CCVigilShared
import Darwin
import Dispatch
import Foundation
import os

enum CLISocketError: Error {
    case syscall(String, Int32)
}

final class CLISocketServer: @unchecked Sendable {
    static let ioTimeoutSeconds = 5
    static let handlerTimeoutSeconds = 10.0
    static let maxSunPathBytes = 104

    private let socketPath: String
    private let handler: @Sendable (WireRequest) async -> WireResponse
    private var listenDescriptor: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "dev.yasyf.cc-vigil.cli.accept")
    private let connectionQueue = DispatchQueue(
        label: "dev.yasyf.cc-vigil.cli.connection",
        attributes: .concurrent
    )

    init(socketPath: String, handler: @escaping @Sendable (WireRequest) async -> WireResponse) {
        precondition(
            socketPath.utf8.count < Self.maxSunPathBytes,
            "socket path too long for sun_path: \(socketPath)"
        )
        self.socketPath = socketPath
        self.handler = handler
    }

    func start() throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CLISocketError.syscall("socket", errno) }
        unlink(socketPath)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { sunPath in
            sunPath.copyBytes(from: pathBytes)
        }
        let previousUmask = umask(0o177)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousUmask)
        guard bound == 0 else {
            close(descriptor)
            throw CLISocketError.syscall("bind", errno)
        }
        guard chmod(socketPath, 0o600) == 0 else {
            close(descriptor)
            throw CLISocketError.syscall("chmod", errno)
        }
        guard listen(descriptor, 16) == 0 else {
            close(descriptor)
            throw CLISocketError.syscall("listen", errno)
        }
        listenDescriptor = descriptor
        acceptQueue.async { [self] in acceptLoop() }
        let path = socketPath
        Logger.cli.info("CLI socket listening at \(path, privacy: .public)")
    }

    private func acceptLoop() {
        while true {
            let client = accept(listenDescriptor, nil, nil)
            guard client >= 0 else {
                if errno == EINTR {
                    continue
                }
                Logger.cli.error("accept failed: errno \(errno, privacy: .public); stopping CLI socket")
                return
            }
            connectionQueue.async { [self] in serve(client) }
        }
    }

    private func serve(_ descriptor: Int32) {
        defer { close(descriptor) }
        // Nudge peers fire-and-forget: they close before reading the reply, so a
        // write to the gone peer must return EPIPE rather than raise SIGPIPE and
        // kill the daemon. SO_NOSIGPIPE is per-socket and not inherited by accept.
        var noSigPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: Self.ioTimeoutSeconds, tv_usec: 0)
        let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize)
        switch readRequest(descriptor) {
        case let .success(request):
            send(bridge(request), to: descriptor)
        case let .failure(message):
            send(.error(message: message), to: descriptor)
        case .disconnected:
            return
        }
    }

    private enum ReadResult {
        case success(WireRequest)
        case failure(String)
        case disconnected
    }

    private func readRequest(_ descriptor: Int32) -> ReadResult {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while buffer.count <= WireFrame.maxPayloadBytes + WireFrame.headerBytes {
            do {
                if let (request, _) = try WireCodec.decodeFrame(WireRequest.self, from: buffer) {
                    return .success(request)
                }
            } catch {
                return .failure("malformed request: \(String(describing: error))")
            }
            let received = recv(descriptor, &chunk, chunk.count, 0)
            guard received > 0 else {
                return buffer.isEmpty ? .disconnected : .failure("request truncated")
            }
            buffer.append(contentsOf: chunk[0 ..< received])
        }
        return .failure("request exceeds frame cap")
    }

    private func bridge(_ request: WireRequest) -> WireResponse {
        let box = OSAllocatedUnfairLock<WireResponse?>(initialState: nil)
        let done = DispatchSemaphore(value: 0)
        let handler = handler
        Task {
            let response = await handler(request)
            box.withLock { $0 = response }
            done.signal()
        }
        // The confirmed-clear loop can outrun the default handler cap; give only
        // that op the wider clear budget so a slow pmset is not cut short, rather
        // than loosening the cap that keeps every other op honest.
        let budget = request == .clear ? ClearBudget.socketHandlerSeconds : Self.handlerTimeoutSeconds
        guard done.wait(timeout: .now() + budget) == .success,
              let response = box.withLock({ $0 })
        else {
            return .error(message: "daemon did not respond in time")
        }
        return response
    }

    private func send(_ response: WireResponse, to descriptor: Int32) {
        let frame: Data
        do {
            frame = try WireCodec.encodeFrame(response)
        } catch {
            Logger.cli.error("response encode failed: \(String(describing: error), privacy: .public)")
            return
        }
        frame.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(descriptor, base + offset, raw.count - offset)
                guard written > 0 else {
                    Logger.cli.debug("CLI reply write ended early (errno \(errno, privacy: .public)); peer disconnected")
                    return
                }
                offset += written
            }
        }
    }
}
