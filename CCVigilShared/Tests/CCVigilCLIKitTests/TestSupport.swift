import CCVigilShared
import CCVigilTransport
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

func withCLIDaemonClient<Result>(
    path: String,
    timeoutSeconds: Int,
    _ body: (CLIDaemonClient) async throws -> Result
) async throws -> Result {
    let client = CLIDaemonClient(path: path, timeoutSeconds: timeoutSeconds)
    do {
        let result = try await body(client)
        await client.close()
        return result
    } catch {
        await client.close()
        throw error
    }
}

enum FakeReply {
    case respond(WireResponse)
    case delayedRespond(WireResponse, afterSeconds: TimeInterval)
    case cancellableStatusThenRespond(WireResponse)
    case raw(Data)
    case silence
}

private actor FakeRequestSignal {
    private var recorded: [WireRequest] = []
    private var waiters: [(WireRequest, CheckedContinuation<Void, Never>)] = []

    func record(_ request: WireRequest) {
        recorded.append(request)
        let matching = waiters.filter { $0.0 == request }
        waiters.removeAll { $0.0 == request }
        for waiter in matching {
            waiter.1.resume()
        }
    }

    func wait(for request: WireRequest) async {
        if recorded.contains(request) {
            return
        }
        await withCheckedContinuation { waiters.append((request, $0)) }
    }
}

final class FakeSocketServer: @unchecked Sendable {
    let path: String
    private let reply: FakeReply
    private let recorded = OSAllocatedUnfairLock<[WireRequest]>(initialState: [])
    private let signal = FakeRequestSignal()
    private let server: SocketServer

    init(path: String, wireBuild: String = WireProtocol.wireBuild, reply: FakeReply) {
        self.path = path
        self.reply = reply
        var configuration = SocketServer.Configuration()
        configuration.maximumSessions = 1
        server = SocketServer(
            path: path,
            wireBuild: wireBuild,
            configuration: configuration,
            trust: .sameEffectiveUser
        ) { [recorded, signal] request in
            guard request.operation == WireProtocol.operation,
                  let decoded = try? WireCodec.decodePayload(WireRequest.self, from: request.payload)
            else {
                return .terminal(SocketTerminal(rejected: true, reason: "invalid test request"))
            }
            recorded.withLock { $0.append(decoded) }
            await signal.record(decoded)
            switch reply {
            case let .respond(response):
                return Self.terminal(response)
            case let .delayedRespond(response, afterSeconds):
                try? await Task.sleep(for: .seconds(afterSeconds))
                return Self.terminal(response)
            case let .cancellableStatusThenRespond(response):
                if decoded == .status {
                    try? await Task.sleep(for: .seconds(60))
                }
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

    func waitForRequest(_ request: WireRequest) async {
        await signal.wait(for: request)
    }

    func withStarted<Result>(_ body: () async throws -> Result) async throws -> Result {
        try await server.start()
        do {
            let result = try await body()
            await stop()
            return result
        } catch {
            await stop()
            throw error
        }
    }

    private func stop() async {
        await server.stop()
    }

    private static func terminal(_ response: WireResponse) -> SocketResponse {
        do {
            return try .terminal(SocketTerminal(payload: WireCodec.encodePayload(response)))
        } catch {
            return .terminal(SocketTerminal(error: String(describing: error)))
        }
    }
}
