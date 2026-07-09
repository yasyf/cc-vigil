import Foundation

/// The latest background work a session's Stop/SubagentStop payload reported
/// still running: `background_tasks` (run_in_background Bash, subagents,
/// monitors, …) and `session_crons` (scheduled prompts). Claude Code v2.1.145+
/// sends both arrays whenever a session stops. A Stop payload is a whole-session
/// snapshot, so it replaces the entry outright and erases it when no work
/// remains; a SubagentStop describes only the finishing subagent and may only
/// add or refresh a positive report (see `apply`).
public struct BackgroundWorkReport: Equatable, Sendable {
    public let backgroundTasks: Int
    public let sessionCrons: Int
    public let epoch: Int64

    public init(backgroundTasks: Int, sessionCrons: Int, epoch: Int64) {
        self.backgroundTasks = backgroundTasks
        self.sessionCrons = sessionCrons
        self.epoch = epoch
    }
}

public struct BackgroundWorkTracker: Equatable, Sendable {
    public static let stopHookEvents: Set<String> = ["Stop", "SubagentStop"]

    public private(set) var reportsBySessionID: [String: BackgroundWorkReport] = [:]

    public init() {}

    /// Only a Stop payload is a whole-session snapshot: it may replace or erase
    /// the entry, so its zero/missing counts clear the report. A SubagentStop's
    /// arrays describe only the finishing subagent — there is no evidence they
    /// are session-wide — so it may set or refresh a positive report but never
    /// clears on zero/missing, lest a subagent finishing wipe a live top-level
    /// run_in_background job (fail toward awake). UserPromptSubmit never reaches
    /// here: background jobs survive new turns, which is exactly why the
    /// transcript alone cannot see them, so a fresh prompt never touches the entry.
    public mutating func apply(_ nudge: NudgePayload, now: Date) {
        guard let sessionID = nudge.sessionId,
              let hookEvent = nudge.hookEvent,
              Self.stopHookEvents.contains(hookEvent)
        else { return }
        let tasks = nudge.backgroundTasks ?? 0
        let crons = nudge.sessionCrons ?? 0
        if tasks == 0, crons == 0 {
            if hookEvent == "Stop" {
                reportsBySessionID.removeValue(forKey: sessionID)
            }
            return
        }
        reportsBySessionID[sessionID] = BackgroundWorkReport(
            backgroundTasks: tasks,
            sessionCrons: crons,
            epoch: Int64(now.timeIntervalSince1970)
        )
    }

    public func reports(forPaths paths: [String]) -> [String: BackgroundWorkReport] {
        var reports: [String: BackgroundWorkReport] = [:]
        for path in paths {
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let report = reportsBySessionID[stem] {
                reports[path] = report
            }
        }
        return reports
    }
}
