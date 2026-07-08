import CCVigilAppKit
import CCVigilShared
import Foundation
import os

/// Subscribes to the daemon's status pushes over the app XPC service and
/// reconnects with generation counters when the connection drops.
@MainActor
final class DaemonClient {
    private let onEvent: (StatusViewModel.Event) -> Void
    private var connection: NSXPCConnection?
    private var generation: UInt64 = 0
    private var backoff = Backoff()

    init(onEvent: @escaping (StatusViewModel.Event) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        connect()
    }

    private func connect() {
        let connection = NSXPCConnection(machServiceName: AppXPC.machServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: AppXPCProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: AppXPCClientProtocol.self)
        generation &+= 1
        let opened = generation
        connection.exportedObject = StatusReceiver { [weak self] payload in
            Task { @MainActor in self?.receive(payload, generation: opened) }
        }
        // These handlers run on XPC's queue: they must be @Sendable, or the
        // closure literal would infer MainActor isolation and trap off-main.
        connection.interruptionHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.drop(generation: opened, reason: "interrupted") }
        }
        connection.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.drop(generation: opened, reason: "invalidated") }
        }
        connection.resume()
        self.connection = connection
        subscribe(over: connection, generation: opened)
    }

    private func subscribe(over connection: NSXPCConnection, generation opened: UInt64) {
        let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable [weak self] error in
            let reason = String(describing: error)
            Task { @MainActor in self?.drop(generation: opened, reason: reason) }
        }
        guard let daemon = proxy as? AppXPCProtocol else {
            drop(generation: opened, reason: "proxy does not conform to AppXPCProtocol")
            return
        }
        daemon.subscribe { [weak self] snapshot in
            Task { @MainActor in self?.receive(snapshot, generation: opened) }
        }
    }

    private func receive(_ payload: Data, generation received: UInt64) {
        guard received == generation, connection != nil else { return }
        backoff.reset()
        do {
            let report = try WireCodec.decodePayload(StatusReport.self, from: payload)
            onEvent(.statusUpdated(report))
        } catch {
            Logger.app.fault("status payload undecodable: \(String(describing: error), privacy: .public)")
        }
    }

    private func drop(generation dropped: UInt64, reason: String) {
        guard dropped == generation, let connection else { return }
        Logger.app.error("daemon connection dropped: \(reason, privacy: .public)")
        self.connection = nil
        connection.invalidate()
        onEvent(.disconnected)
        let delay = backoff.next()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.connection == nil else { return }
            connect()
        }
    }
}

private final class StatusReceiver: NSObject, AppXPCClientProtocol {
    private let deliver: @Sendable (Data) -> Void

    init(deliver: @escaping @Sendable (Data) -> Void) {
        self.deliver = deliver
    }

    func statusChanged(_ statusJSON: Data) {
        deliver(statusJSON)
    }
}
