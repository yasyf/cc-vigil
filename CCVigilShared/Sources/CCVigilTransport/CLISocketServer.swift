import CCVigilShared
import DaemonKit
import Foundation
import os

private let cliSocketLog = Logger(subsystem: "dev.yasyf.cc-vigil", category: "CLISocket")

public final class CLISocketServer: @unchecked Sendable {
    public static let maximumActiveRequests = 8

    private let socketPath: String
    private let runtime: StaticSessionServiceRuntime<WireRequest, WireResponse>

    public init(
        socketPath: String,
        runtimeBuild: String,
        handler: @escaping @Sendable (WireRequest) async -> WireResponse
    ) throws {
        self.socketPath = socketPath
        runtime = try StaticSessionServiceRuntime(
            path: socketPath,
            wireBuild: WireProtocol.wireBuild,
            runtimeBuild: runtimeBuild,
            role: WireProtocol.clientRole,
            trust: .sameEffectiveUser,
            configuration: SessionServiceConfiguration(
                maximumFrameBytes: daemonKitDefaultMaximumFrameBytes,
                maximumRequestBytes: 1024 * 1024,
                maximumActiveRequests: Self.maximumActiveRequests,
                maximumSessions: 16,
                streamQueueDepth: 8,
                maximumPendingWrites: 16,
                handshakeTimeout: 5,
                writeTimeout: 5
            ),
            handler: SessionServiceHandler(
                operation: WireProtocol.operation,
                tenant: "",
                codec: SessionServiceCodec(
                    decodeRequest: { try WireCodec.decodePayload(WireRequest.self, from: $0) },
                    encodeResponse: { try WireCodec.encodePayload($0) }
                ),
                handle: handler
            )
        )
    }

    public func start() async throws {
        try await runtime.start(deadline: Date().addingTimeInterval(5))
        let path = socketPath
        cliSocketLog.info("CLI socket listening at \(path, privacy: .public)")
    }

    public func stop() async {
        do {
            try await runtime.shutdown(deadline: Date().addingTimeInterval(5))
        } catch {
            cliSocketLog.error("CLI socket shutdown failed: \(String(describing: error), privacy: .public)")
        }
    }
}
