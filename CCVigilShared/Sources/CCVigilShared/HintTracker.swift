import Foundation

public struct HintTracker: Equatable, Sendable {
    public static let waitHookEvent = "Notification"
    public static let clearHookEvent = "UserPromptSubmit"

    public private(set) var waitEpochsBySessionID: [String: Int64] = [:]

    public init() {}

    public mutating func apply(_ nudge: NudgePayload, now: Date) {
        guard let sessionID = nudge.sessionId else { return }
        switch nudge.hookEvent {
        case Self.waitHookEvent:
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
