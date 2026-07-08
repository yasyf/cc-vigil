import Foundation

public struct HintTracker: Equatable, Sendable {
    public static let waitHookEvent = "Notification"
    public static let clearHookEvent = "UserPromptSubmit"

    public private(set) var waitEpochsBySessionID: [String: Int64] = [:]

    public init() {}

    /// Claude Code's Notification hook fires for machine events too (an agent
    /// completed, a login succeeded); only the notifications that park the turn on
    /// a human set a wait hint. A missing or unrecognized kind fails toward
    /// staying awake — it records no hint, because setting one pushes the session
    /// toward being discounted, and a sleep inhibitor must never sleep on
    /// ambiguity. The oracle's activity window and max-age backstop still discount
    /// a genuinely parked session, and older CLI builds that omit
    /// notification_type keep blocking until they do.
    private static let humanWaitKinds: Set<String> = [
        "idle_prompt", "agent_needs_input", "elicitation_dialog",
    ]

    private static func isHumanWaiting(_ kind: String?) -> Bool {
        guard let kind else { return false }
        return humanWaitKinds.contains(kind) || kind.hasSuffix("permission_prompt")
    }

    public mutating func apply(_ nudge: NudgePayload, now: Date) {
        guard let sessionID = nudge.sessionId else { return }
        switch nudge.hookEvent {
        case Self.waitHookEvent:
            guard Self.isHumanWaiting(nudge.notificationKind) else { break }
            waitEpochsBySessionID[sessionID] = Int64(now.timeIntervalSince1970)
        case Self.clearHookEvent:
            waitEpochsBySessionID.removeValue(forKey: sessionID)
        default:
            break
        }
    }

    public func hints(forPaths paths: [String]) -> [String: Int64] {
        var hints: [String: Int64] = [:]
        for path in paths {
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let epoch = waitEpochsBySessionID[stem] {
                hints[path] = epoch
            }
        }
        return hints
    }
}
