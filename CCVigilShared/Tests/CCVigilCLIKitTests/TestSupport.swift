import CCVigilShared
import DaemonKit
import Foundation
import os

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
    case delayedRespond(WireResponse, afterSeconds: TimeInterval)
    case raw(Data)
    case silence
}

final class FakeSocketServer: @unchecked Sendable {
    let path: String
    private let reply: FakeReply
    private let recorded = OSAllocatedUnfairLock<[WireRequest]>(initialState: [])
    private let server: SocketServer

    init(path: String, build: String = WireProtocol.build, reply: FakeReply) {
        self.path = path
        self.reply = reply
        server = SocketServer(
            path: path,
            build: build,
            trust: .sameEffectiveUser
        ) { [recorded] request in
            guard request.operation == WireProtocol.operation,
                  let decoded = try? WireCodec.decodePayload(WireRequest.self, from: request.payload)
            else {
                return .terminal(SocketTerminal(rejected: true, reason: "invalid test request"))
            }
            recorded.withLock { $0.append(decoded) }
            switch reply {
            case let .respond(response):
                return Self.terminal(response)
            case let .delayedRespond(response, afterSeconds):
                try? await Task.sleep(for: .seconds(afterSeconds))
                return Self.terminal(response)
            case let .raw(payload):
                return .terminal(SocketTerminal(payload: payload))
            case .silence:
                try? await Task.sleep(for: .seconds(60))
                return .terminal(SocketTerminal(error: "wire: request canceled"))
            }
        }
    }

    var requests: [WireRequest] {
        recorded.withLock { $0 }
    }

    func start() throws {
        try server.start()
    }

    func stop() {
        server.stop()
    }

    private static func terminal(_ response: WireResponse) -> SocketResponse {
        do {
            return try .terminal(SocketTerminal(payload: WireCodec.encodePayload(response)))
        } catch {
            return .terminal(SocketTerminal(error: String(describing: error)))
        }
    }
}
