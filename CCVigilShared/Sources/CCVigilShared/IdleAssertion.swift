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
    public let localizationBundlePath: String
    public let timeout: TimeInterval
    public let timeoutAction: IdleAssertionTimeoutAction

    public init(
        type: IdleAssertionType,
        name: String,
        reason: String,
        details: String,
        localizationBundlePath: String,
        timeout: TimeInterval,
        timeoutAction: IdleAssertionTimeoutAction
    ) {
        self.type = type
        self.name = name
        self.reason = reason
        self.details = details
        self.localizationBundlePath = localizationBundlePath
        self.timeout = timeout
        self.timeoutAction = timeoutAction
    }

    /// The dead-man timeout: the daemon re-pushes every 60 s (re-arming it), so
    /// only a wedged helper that stops re-pushing loses the hold after 15 min.
    public static let deadManTimeout: TimeInterval = 900

    /// The attributed descriptor cc-vigil holds while agents work. The type is
    /// fixed to system-idle sleep: the display-sleep-never-inhibited invariant
    /// means `IdleAssertionType` has no display case to reach. `IOPMLib` requires
    /// the localization bundle path alongside the human-readable reason; the caller
    /// derives it from the running helper's executable with
    /// ``appBundlePath(forHelperExecutableAt:)``.
    public static func ccVigil(localizationBundlePath: String) -> IdleAssertionDescriptor {
        IdleAssertionDescriptor(
            type: .preventUserIdleSystemSleep,
            name: "cc-vigil: agents active",
            reason: "Claude Code agents are working; cc-vigil is holding the system awake",
            details: "cc-vigil helper",
            localizationBundlePath: localizationBundlePath,
            timeout: deadManTimeout,
            timeoutAction: .release
        )
    }

    /// The helper installs at `CCVigil.app/Contents/Library/LaunchDaemons/<binary>`
    /// and its localizable assertion strings live in the enclosing `.app`. Walk the
    /// executable's ancestors up to that bundle. The installed layout always nests
    /// the helper inside a `.app`, so a missing bundle is an unexpected state.
    public static func appBundlePath(forHelperExecutableAt executable: URL) -> String {
        var directory = executable.deletingLastPathComponent()
        while directory.pathExtension != "app" {
            let parent = directory.deletingLastPathComponent()
            precondition(parent != directory, "helper executable \(executable.path) is not inside a .app bundle")
            directory = parent
        }
        return directory.path
    }
}
