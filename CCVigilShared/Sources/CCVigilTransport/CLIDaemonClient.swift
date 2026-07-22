import CCVigilShared
import DaemonKit
import Foundation
import os

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

    private let lock = NSLock()
    private var session: SocketClient?

    public init(path: String, timeoutSeconds: Int = CLIDaemonClient.defaultTimeoutSeconds) {
        precondition(timeoutSeconds > 0, "socket timeout must be positive")
        self.path = path
        self.timeoutSeconds = timeoutSeconds
    }

    public static func timeout(for request: WireRequest) -> Int {
        switch request {
        case .clear: ClearBudget.clientSeconds
        default: defaultTimeoutSeconds
        }
    }

    public func roundTrip(_ request: WireRequest) throws -> WireResponse {
        let result = OSAllocatedUnfairLock<Result<WireResponse, Error>?>(initialState: nil)
        let settled = DispatchSemaphore(value: 0)
        Task.detached {
            let response: Result<WireResponse, Error>
            do {
                response = try await .success(self.roundTrip(request))
            } catch {
                response = .failure(error)
            }
            result.withLock { $0 = response }
            settled.signal()
        }
        settled.wait()
        guard let response = result.withLock({ $0 }) else {
            throw DaemonClientError.transport("request task settled without a result")
        }
        return try response.get()
    }

    public func roundTrip(_ request: WireRequest) async throws -> WireResponse {
        let client: SocketClient
        do {
            client = try currentSession()
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
        } catch {
            invalidate()
            throw DaemonClientError.transport(String(describing: error))
        }
    }

    public func close() {
        lock.lock()
        let active = session
        session = nil
        lock.unlock()
        active?.close()
    }

    private func currentSession() throws -> SocketClient {
        lock.lock()
        defer { lock.unlock() }
        if let session {
            return session
        }
        let opened = try SocketClient(
            path: path,
            build: WireProtocol.build,
            trust: .sameEffectiveUser
        )
        guard opened.peerBuild == WireProtocol.build else {
            opened.close()
            throw DaemonClientError.rejected(
                "build \(opened.peerBuild) does not match \(WireProtocol.build)"
            )
        }
        session = opened
        return opened
    }

    private func invalidate() {
        close()
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
