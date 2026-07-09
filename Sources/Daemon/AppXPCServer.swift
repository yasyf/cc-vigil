import CCVigilDaemonKit
import CCVigilShared
import Foundation
import os

final class StatusBroadcaster: @unchecked Sendable {
    private let subscribers = OSAllocatedUnfairLock<[ObjectIdentifier: NSXPCConnection]>(
        uncheckedState: [:]
    )

    func add(_ connection: NSXPCConnection) {
        subscribers.withLockUnchecked { $0[ObjectIdentifier(connection)] = connection }
    }

    func remove(_ id: ObjectIdentifier) {
        subscribers.withLockUnchecked { _ = $0.removeValue(forKey: id) }
    }

    func broadcast(_ statusJSON: Data) {
        let connections = subscribers.withLockUnchecked { Array($0.values) }
        for connection in connections {
            (connection.remoteObjectProxy as? AppXPCClientProtocol)?.statusChanged(statusJSON)
        }
    }
}

final class AppXPCService: NSObject, AppXPCProtocol, @unchecked Sendable {
    private let broadcaster: StatusBroadcaster
    private let statusProvider: @Sendable () async -> Data?

    init(broadcaster: StatusBroadcaster, statusProvider: @escaping @Sendable () async -> Data?) {
        self.broadcaster = broadcaster
        self.statusProvider = statusProvider
    }

    func subscribe(reply: @escaping @Sendable (Data) -> Void) {
        guard let connection = NSXPCConnection.current() else {
            AppStatusSubscription.deliver(snapshot: nil, reply: reply)
            return
        }
        broadcaster.add(connection)
        let statusProvider = statusProvider
        Task {
            await AppStatusSubscription.deliver(snapshot: statusProvider(), reply: reply)
        }
    }
}

final class AppXPCServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let listener: NSXPCListener
    private let broadcaster: StatusBroadcaster
    private let service: AppXPCService
    private let verifier: CallerVerifier

    init(
        broadcaster: StatusBroadcaster,
        verifier: CallerVerifier,
        statusProvider: @escaping @Sendable () async -> Data?
    ) {
        listener = NSXPCListener(machServiceName: AppXPC.machServiceName)
        self.broadcaster = broadcaster
        self.verifier = verifier
        service = AppXPCService(broadcaster: broadcaster, statusProvider: statusProvider)
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
        Logger.daemon.info("app XPC listening on \(AppXPC.machServiceName, privacy: .public)")
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard verifier.shouldAccept(auditToken: newConnection.auditTokenData) else {
            Logger.daemon.error(
                "rejected app XPC peer pid \(newConnection.processIdentifier, privacy: .public)"
            )
            return false
        }
        newConnection.exportedInterface = NSXPCInterface(with: AppXPCProtocol.self)
        newConnection.exportedObject = service
        newConnection.remoteObjectInterface = NSXPCInterface(with: AppXPCClientProtocol.self)
        let id = ObjectIdentifier(newConnection)
        let broadcaster = broadcaster
        newConnection.invalidationHandler = { broadcaster.remove(id) }
        newConnection.resume()
        return true
    }
}
