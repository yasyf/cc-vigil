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
    private let server: StaticSessionServiceRuntime<WireRequest, Data>

    init(path: String, wireBuild: String = WireProtocol.wireBuild, reply: FakeReply) throws {
        self.path = path
        self.reply = reply
        server = try StaticSessionServiceRuntime(
            path: path,
            wireBuild: wireBuild,
            runtimeBuild: "cc-vigil-test.v1",
            role: WireProtocol.clientRole,
            trust: .sameEffectiveUser,
            configuration: SessionServiceConfiguration(
                maximumFrameBytes: daemonKitDefaultMaximumFrameBytes,
                maximumRequestBytes: 1024 * 1024,
                maximumActiveRequests: CLISocketServer.maximumActiveRequests,
                maximumSessions: 1,
                streamQueueDepth: 8,
                maximumPendingWrites: 16,
                handshakeTimeout: 2,
                writeTimeout: 2
            ),
            handler: SessionServiceHandler(
                operation: WireProtocol.operation,
                tenant: "",
                codec: SessionServiceCodec(
                    decodeRequest: { try WireCodec.decodePayload(WireRequest.self, from: $0) },
                    encodeResponse: { $0 }
                )
            ) { [recorded, signal] request in
                recorded.withLock { $0.append(request) }
                await signal.record(request)
                switch reply {
                case let .respond(response):
                    return Self.payload(response)
                case let .delayedRespond(response, afterSeconds):
                    try? await Task.sleep(for: .seconds(afterSeconds))
                    return Self.payload(response)
                case let .cancellableStatusThenRespond(response):
                    if request == .status {
                        try? await Task.sleep(for: .seconds(60))
                    }
                    return Self.payload(response)
                case let .raw(payload):
                    return payload
                case .silence:
                    try? await Task.sleep(for: .seconds(60))
                    return Data(#"{"error":"wire: request canceled"}"#.utf8)
                }
            }
        )
    }

    var requests: [WireRequest] {
        recorded.withLock { $0 }
    }

    func waitForRequest(_ request: WireRequest) async {
        await signal.wait(for: request)
    }

    func withStarted<Result>(_ body: () async throws -> Result) async throws -> Result {
        try await start()
        do {
            let result = try await body()
            await stop()
            return result
        } catch {
            await stop()
            throw error
        }
    }

    func start() async throws {
        try await server.start(deadline: Date().addingTimeInterval(2))
    }

    func stop() async {
        try? await server.shutdown(deadline: Date().addingTimeInterval(2))
    }

    private static func payload(_ response: WireResponse) -> Data {
        (try? WireCodec.encodePayload(response)) ?? Data("null".utf8)
    }
}
