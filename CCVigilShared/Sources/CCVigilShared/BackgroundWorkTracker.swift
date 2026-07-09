import Foundation

/// The latest background work a session's Stop/SubagentStop payload reported
/// still running: `background_tasks` (run_in_background Bash, subagents,
/// monitors, …) and `session_crons` (scheduled prompts). Claude Code v2.1.145+
/// sends both arrays whenever a session stops, so each report replaces the last
/// outright and a stop with no remaining work erases the entry.
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

    /// UserPromptSubmit deliberately never clears a report: background jobs
    /// survive new turns, which is exactly why the transcript alone cannot see
    /// them. Only the next Stop/SubagentStop — whose payload is the whole truth
    /// about what still runs — updates or erases the entry.
    public mutating func apply(_ nudge: NudgePayload, now: Date) {
        guard let sessionID = nudge.sessionId,
              let hookEvent = nudge.hookEvent,
              Self.stopHookEvents.contains(hookEvent)
        else { return }
        let tasks = nudge.backgroundTasks ?? 0
        let crons = nudge.sessionCrons ?? 0
        if tasks == 0, crons == 0 {
            reportsBySessionID.removeValue(forKey: sessionID)
        } else {
            reportsBySessionID[sessionID] = BackgroundWorkReport(
                backgroundTasks: tasks,
                sessionCrons: crons,
                epoch: Int64(now.timeIntervalSince1970)
            )
        }
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
