import CCVigilShared
import Darwin
import Foundation
import os

enum FakeServerError: Error {
    case syscall(String, Int32)
}

struct ShortTempDir {
    let url: URL

    init(prefix: String) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func path(_ name: String) -> String {
        url.appendingPathComponent(name).path
    }

    func socketPath(_ name: String) -> String {
        let path = path(name)
        precondition(path.utf8.count < 104, "socket path too long for sun_path: \(path)")
        return path
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }
}

enum FakeReply {
    case respond(WireResponse)
    case raw(Data)
    case silence
}

final class FakeSocketServer: @unchecked Sendable {
    let path: String
    private let reply: FakeReply
    private let recorded = OSAllocatedUnfairLock<[WireRequest]>(initialState: [])
    private let parked = OSAllocatedUnfairLock<[Int32]>(initialState: [])
    private var listenDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "fake-socket-server")

    init(path: String, reply: FakeReply) {
        precondition(path.utf8.count < 104, "socket path too long for sun_path: \(path)")
        self.path = path
        self.reply = reply
    }

    var requests: [WireRequest] {
        recorded.withLock { $0 }
    }

    func start() throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw FakeServerError.syscall("socket", errno) }
        unlink(path)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { sunPath in
            sunPath.copyBytes(from: pathBytes)
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 8) == 0 else {
            close(descriptor)
            throw FakeServerError.syscall("bind/listen", errno)
        }
        listenDescriptor = descriptor
        queue.async { [self] in acceptLoop() }
    }

    func stop() {
        close(listenDescriptor)
        parked.withLock { descriptors in
            for descriptor in descriptors {
                close(descriptor)
            }
            descriptors.removeAll()
        }
        unlink(path)
    }

    private func acceptLoop() {
        while true {
            let client = accept(listenDescriptor, nil, nil)
            guard client >= 0 else { return }
            serve(client)
        }
    }

    private func serve(_ descriptor: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            if let (request, _) = try? WireCodec.decodeFrame(WireRequest.self, from: buffer) {
                recorded.withLock { $0.append(request) }
                break
            }
            let received = recv(descriptor, &chunk, chunk.count, 0)
            guard received > 0 else {
                close(descriptor)
                return
            }
            buffer.append(contentsOf: chunk[0 ..< received])
        }
        switch reply {
        case let .respond(response):
            if let frame = try? WireCodec.encodeFrame(response) {
                sendAll(frame, to: descriptor)
            }
            close(descriptor)
        case let .raw(data):
            sendAll(data, to: descriptor)
            close(descriptor)
        case .silence:
            parked.withLock { $0.append(descriptor) }
        }
    }

    private func sendAll(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(descriptor, base + offset, raw.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }
}
