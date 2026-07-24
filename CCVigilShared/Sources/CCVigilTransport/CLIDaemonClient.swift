import CCVigilShared
import DaemonKit
import Foundation

public enum DaemonClientError: Error, Equatable, CustomStringConvertible {
    case rejected(String)
    case remote(String)
    case timedOut
    case missingReply
    case malformedReply(String)
    case transport(String)

    public var description: String {
        switch self {
        case let .rejected(reason):
            "daemon rejected the request: \(reason)"
        case let .remote(message):
            "daemon transport failed: \(message)"
        case .timedOut:
            "daemon request timed out"
        case .missingReply:
            "daemon returned no reply payload"
        case let .malformedReply(detail):
            "malformed reply from the daemon: \(detail)"
        case let .transport(detail):
            "daemon session failed: \(detail)"
        }
    }
}

public final class CLIDaemonClient: @unchecked Sendable {
    public static let defaultTimeoutSeconds = 5

    public let path: String
    public let timeoutSeconds: Int

    private let session = CLIDaemonSession()

    public init(path: String, timeoutSeconds: Int = CLIDaemonClient.defaultTimeoutSeconds) {
        precondition(timeoutSeconds > 0, "socket timeout must be positive")
        self.path = path
        self.timeoutSeconds = timeoutSeconds
    }

    deinit {
        let session = session
        Task { await session.reset() }
    }

    public static func timeout(for request: WireRequest) -> Int {
        switch request {
        case .clear: ClearBudget.clientSeconds
        default: defaultTimeoutSeconds
        }
    }

    public func roundTrip(_ request: WireRequest) async throws -> WireResponse {
        let requestTimeout = request == .clear
            ? max(timeoutSeconds, Self.timeout(for: request))
            : timeoutSeconds
        let deadline = Date().addingTimeInterval(TimeInterval(requestTimeout))
        do {
            let client = try await session.current(path: path, wireBuild: WireProtocol.wireBuild)
            let terminal = try await client.call(ServiceSocketCall(
                operation: WireProtocol.operation,
                payload: WireCodec.encodePayload(request),
                runtimeTarget: .anyAuthenticatedSuccessor,
                deadline: deadline
            ))
            return try decode(terminal)
        } catch let error as DaemonClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ServiceSocketRejectionError {
            throw DaemonClientError.rejected(error.reason)
        } catch let error as SocketHandshakeRejectionError {
            throw DaemonClientError.rejected(error.reason)
        } catch let error as SocketWireBuildMismatchError {
            throw DaemonClientError.rejected(error.description)
        } catch ServiceSocketClientError.deadlineExceeded {
            await session.reset()
            guard FileManager.default.fileExists(atPath: path) else {
                throw DaemonClientError.transport("daemon socket is unavailable")
            }
            throw DaemonClientError.timedOut
        } catch is SocketCallDeadlineExceededError {
            await session.reset()
            throw DaemonClientError.timedOut
        } catch {
            await session.reset()
            throw DaemonClientError.transport(String(describing: error))
        }
    }

    public func close() async {
        await session.reset()
    }

    private func decode(_ terminal: SocketTerminal) throws -> WireResponse {
        if terminal.rejected {
            throw DaemonClientError.rejected(terminal.reason ?? "unspecified rejection")
        }
        if let error = terminal.error {
            if error == "wire: request canceled" {
                throw DaemonClientError.timedOut
            }
            throw DaemonClientError.remote(error)
        }
        guard let payload = terminal.payload else {
            throw DaemonClientError.missingReply
        }
        do {
            return try WireCodec.decodePayload(WireResponse.self, from: payload)
        } catch {
            throw DaemonClientError.malformedReply(String(describing: error))
        }
    }
}

private actor CLIDaemonSession {
    private var client: ServiceSocketClient?

    func current(path: String, wireBuild: String) throws -> ServiceSocketClient {
        if let client {
            return client
        }
        let client = try ServiceSocketClient(
            path: path,
            wireBuild: wireBuild,
            role: WireProtocol.clientRole,
            noProgressTimeout: TimeInterval(CLIDaemonClient.defaultTimeoutSeconds)
        )
        self.client = client
        return client
    }

    func reset() async {
        let previous = client
        client = nil
        await previous?.close()
    }
}
