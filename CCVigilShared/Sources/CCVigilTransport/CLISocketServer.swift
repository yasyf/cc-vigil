import CCVigilShared
import DaemonKit
import Foundation
import os

private let cliSocketLog = Logger(subsystem: "dev.yasyf.cc-vigil", category: "CLISocket")

public final class CLISocketServer: @unchecked Sendable {
    public static let maximumActiveRequests = 8

    private let socketPath: String
    private let server: SocketServer

    public init(
        socketPath: String,
        handler: @escaping @Sendable (WireRequest) async -> WireResponse
    ) {
        self.socketPath = socketPath
        var configuration = SocketServer.Configuration()
        configuration.maximumActiveRequests = Self.maximumActiveRequests
        server = SocketServer(
            path: socketPath,
            wireBuild: WireProtocol.wireBuild,
            configuration: configuration,
            trust: .sameEffectiveUser
        ) { request in
            await Self.respond(to: request, handler: handler)
        }
    }

    public func start() async throws {
        try await server.start()
        let path = socketPath
        cliSocketLog.info("CLI socket listening at \(path, privacy: .public)")
    }

    public func stop() async {
        await server.stop()
    }

    private static func respond(
        to request: SocketRequest,
        handler: @escaping @Sendable (WireRequest) async -> WireResponse
    ) async -> SocketResponse {
        guard request.operation == WireProtocol.operation, request.tenant.isEmpty else {
            return .terminal(SocketTerminal(
                rejected: true,
                reason: "cc-vigil: unsupported operation"
            ))
        }
        let decoded: WireRequest
        do {
            decoded = try WireCodec.decodePayload(WireRequest.self, from: request.payload)
        } catch {
            return .terminal(SocketTerminal(
                rejected: true,
                reason: "cc-vigil: malformed request"
            ))
        }
        let response = await handler(decoded)
        do {
            return try .terminal(SocketTerminal(payload: WireCodec.encodePayload(response)))
        } catch {
            cliSocketLog.error("response encode failed: \(String(describing: error), privacy: .public)")
            return .terminal(SocketTerminal(error: "cc-vigil: response encode failed"))
        }
    }
}
