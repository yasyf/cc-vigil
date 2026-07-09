import CCVigilShared
import Foundation
import os

actor HelperClient: BlockPushing {
    static let callTimeoutSeconds = ClearBudget.helperCallSeconds

    private var connection: NSXPCConnection?
    private var generation: UInt64 = 0
    private var backoff = Backoff()
    private var retryAt = Date.distantPast
    private var disruptionHandler: (@Sendable () -> Void)?

    func setDisruptionHandler(_ handler: @escaping @Sendable () -> Void) {
        disruptionHandler = handler
    }

    func push(blocked: Bool) async -> BlockPushOutcome {
        guard let connection = ensureConnection() else {
            return .unavailable("helper reconnect backoff until \(retryAt)")
        }
        let callGeneration = generation
        let outcome = await callSetSleepBlocked(blocked, over: connection)
        switch outcome {
        case .applied, .unsettled:
            backoff.reset()
            retryAt = .distantPast
        case .failed:
            dropConnection(generation: callGeneration)
        case .unavailable:
            break
        }
        return outcome
    }

    private func callSetSleepBlocked(
        _ blocked: Bool,
        over connection: NSXPCConnection
    ) async -> BlockPushOutcome {
        var timeout: Task<Void, Never>?
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<BlockPushOutcome, Never>) in
            let resume = ResumeOnce<BlockPushOutcome> { continuation.resume(returning: $0) }
            guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
                resume(.failed(String(describing: error)))
            }) as? HelperXPCProtocol else {
                resume(.failed("helper proxy does not conform to HelperXPCProtocol"))
                return
            }
            helper.setSleepBlocked(blocked) { applied, error in
                if let error {
                    resume(.unsettled(applied: applied, detail: error.localizedDescription))
                } else {
                    resume(.applied(applied))
                }
            }
            timeout = Task {
                try? await Task.sleep(for: .seconds(Self.callTimeoutSeconds))
                // A timeout after send is ambiguous: the helper may have applied it.
                resume(.failed("setSleepBlocked timed out after \(Int(Self.callTimeoutSeconds))s"))
            }
        }
        timeout?.cancel()
        return outcome
    }

    private func ensureConnection() -> NSXPCConnection? {
        if let connection {
            return connection
        }
        guard Date() >= retryAt else { return nil }
        let connection = NSXPCConnection(
            machServiceName: HelperXPC.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        generation &+= 1
        let connectionGeneration = generation
        connection.invalidationHandler = { [weak self] in
            Task { await self?.connectionInvalidated(generation: connectionGeneration) }
        }
        connection.interruptionHandler = { [weak self] in
            Task { await self?.connectionInterrupted(generation: connectionGeneration) }
        }
        connection.resume()
        self.connection = connection
        Logger.helperClient.info("helper connection opened (generation \(connectionGeneration, privacy: .public))")
        return connection
    }

    private func connectionInvalidated(generation invalidated: UInt64) {
        guard invalidated == generation, connection != nil else { return }
        Logger.helperClient.error("helper connection invalidated (generation \(invalidated, privacy: .public))")
        dropConnection(generation: invalidated)
        disruptionHandler?()
    }

    private func connectionInterrupted(generation interrupted: UInt64) {
        guard interrupted == generation else { return }
        // The helper restarted and force-cleared on init: force a re-push.
        Logger.helperClient.error("helper connection interrupted; forcing re-push")
        disruptionHandler?()
    }

    private func dropConnection(generation dropped: UInt64) {
        guard dropped == generation else { return }
        connection?.invalidate()
        connection = nil
        retryAt = Date().addingTimeInterval(backoff.next())
    }
}
