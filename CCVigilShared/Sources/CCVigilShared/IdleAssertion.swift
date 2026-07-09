import Foundation

public enum IdleAssertionType: Equatable, Sendable {
    case preventUserIdleSystemSleep
}

public enum IdleAssertionTimeoutAction: Equatable, Sendable {
    case release
}

public struct IdleAssertionDescriptor: Equatable, Sendable {
    public let type: IdleAssertionType
    public let name: String
    public let reason: String
    public let details: String
    public let timeout: TimeInterval
    public let timeoutAction: IdleAssertionTimeoutAction

    public init(
        type: IdleAssertionType,
        name: String,
        reason: String,
        details: String,
        timeout: TimeInterval,
        timeoutAction: IdleAssertionTimeoutAction
    ) {
        self.type = type
        self.name = name
        self.reason = reason
        self.details = details
        self.timeout = timeout
        self.timeoutAction = timeoutAction
    }

    /// The type is fixed to system-idle sleep: the display-sleep-never-inhibited
    /// invariant means IdleAssertionType has no display case to reach. The 900 s
    /// timeout is a dead-man — the daemon re-pushes every 60 s (re-arming it), so
    /// only a wedged helper that stops re-pushing loses the hold after 15 min.
    public static let ccVigil = IdleAssertionDescriptor(
        type: .preventUserIdleSystemSleep,
        name: "cc-vigil: agents active",
        reason: "Claude Code agents are working; cc-vigil is holding the system awake",
        details: "cc-vigil helper",
        timeout: 900,
        timeoutAction: .release
    )
}
