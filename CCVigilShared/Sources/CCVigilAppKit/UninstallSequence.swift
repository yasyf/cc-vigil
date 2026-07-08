import Foundation

/// The uninstall effects, injected so the load-bearing ordering — a confirmed
/// sleep-block clear before the services are unregistered — is testable without
/// the SMAppService, daemon-socket, and filesystem edges.
public struct UninstallSteps: Sendable {
    public let uninstallHooks: @Sendable () async -> String
    public let clearSleepBlock: @Sendable () async -> Bool
    public let unregisterServices: @Sendable () async -> [String]
    public let removeSymlinks: @Sendable () async -> String

    public init(
        uninstallHooks: @escaping @Sendable () async -> String,
        clearSleepBlock: @escaping @Sendable () async -> Bool,
        unregisterServices: @escaping @Sendable () async -> [String],
        removeSymlinks: @escaping @Sendable () async -> String
    ) {
        self.uninstallHooks = uninstallHooks
        self.clearSleepBlock = clearSleepBlock
        self.unregisterServices = unregisterServices
        self.removeSymlinks = removeSymlinks
    }
}

public enum UninstallSequence {
    /// Runs uninstall in the order that keeps sleep from being stranded: remove
    /// hooks, then confirm the sleep block is cleared while the daemon and helper
    /// are still alive and registered, and only then unregister the services and
    /// remove the symlink. Unregistering first would leave the block resting on
    /// SIGKILL-truncatable shutdown handlers.
    public static func run(_ steps: UninstallSteps) async -> [String] {
        var lines: [String] = []
        await lines.append(steps.uninstallHooks())
        let cleared = await steps.clearSleepBlock()
        lines.append(cleared
            ? "cleared the sleep block"
            : "sleep block clear unconfirmed; shutdown handlers will retry")
        await lines.append(contentsOf: steps.unregisterServices())
        await lines.append(steps.removeSymlinks())
        return lines
    }
}
