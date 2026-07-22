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
        Task { await session.abort() }
    }

    public static func timeout(for request: WireRequest) -> Int {
        switch request {
        case .clear: ClearBudget.clientSeconds
        default: defaultTimeoutSeconds
        }
    }

    public func roundTrip(_ request: WireRequest) async throws -> WireResponse {
        let client: SocketClient
        do {
            client = try await session.current(path: path, build: WireProtocol.build)
            let requestTimeout = request == .clear
                ? max(timeoutSeconds, Self.timeout(for: request))
                : timeoutSeconds
            let terminal = try await client.call(
                operation: WireProtocol.operation,
                payload: WireCodec.encodePayload(request),
                deadline: Date().addingTimeInterval(TimeInterval(requestTimeout))
            )
            return try decode(terminal)
        } catch let error as DaemonClientError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch {
            await session.abort()
            throw DaemonClientError.transport(String(describing: error))
        }
    }

    public func close() async {
        await session.close()
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
    private enum State {
        case idle
        case connecting(UUID, Task<SocketClient, Error>)
        case ready(SocketClient)
    }

    private var state = State.idle

    func current(path: String, build: String) async throws -> SocketClient {
        switch state {
        case let .ready(client):
            return client
        case let .connecting(id, task):
            return try await finishConnection(id: id, task: task)
        case .idle:
            let id = UUID()
            let task = Task<SocketClient, Error> {
                let opened = try await SocketClient(
                    path: path,
                    build: build,
                    trust: .sameEffectiveUser
                )
                guard opened.peerBuild == build else {
                    await opened.close()
                    throw DaemonClientError.rejected(
                        "build \(opened.peerBuild) does not match \(build)"
                    )
                }
                return opened
            }
            state = .connecting(id, task)
            return try await finishConnection(id: id, task: task)
        }
    }

    func close() async {
        let previous = state
        state = .idle
        switch previous {
        case let .ready(client):
            await client.close()
        case let .connecting(_, task):
            task.cancel()
            if case let .success(client) = await task.result {
                await client.close()
            }
        case .idle:
            break
        }
    }

    func abort() async {
        let previous = state
        state = .idle
        switch previous {
        case let .ready(client):
            await client.abort()
        case let .connecting(_, task):
            task.cancel()
        case .idle:
            break
        }
    }

    private func finishConnection(
        id: UUID,
        task: Task<SocketClient, Error>
    ) async throws -> SocketClient {
        do {
            let opened = try await task.value
            switch state {
            case let .connecting(currentID, _) where currentID == id:
                state = .ready(opened)
                return opened
            case let .ready(current) where current === opened:
                return opened
            default:
                await opened.close()
                throw DaemonClientError.transport("connection canceled")
            }
        } catch {
            if case let .connecting(currentID, _) = state, currentID == id {
                state = .idle
            }
            throw error
        }
    }
}
