import CCVigilShared
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1000)

private func stop(
    _ sessionID: String? = "abc",
    hookEvent: String = "Stop",
    backgroundTasks: Int? = nil,
    sessionCrons: Int? = nil
) -> NudgePayload {
    NudgePayload(
        sessionId: sessionID,
        hookEvent: hookEvent,
        backgroundTasks: backgroundTasks,
        sessionCrons: sessionCrons
    )
}

@Test(arguments: ["Stop", "SubagentStop"])
func stopWithBackgroundTasksRecordsReport(hookEvent: String) {
    var tracker = BackgroundWorkTracker()
    tracker.apply(stop(hookEvent: hookEvent, backgroundTasks: 2, sessionCrons: 0), now: now)
    #expect(tracker.reportsBySessionID == [
        "abc": BackgroundWorkReport(backgroundTasks: 2, sessionCrons: 0, epoch: 1000),
    ])
}

@Test func stopWithOnlyCronsRecordsReport() {
    var tracker = BackgroundWorkTracker()
    tracker.apply(stop(backgroundTasks: 0, sessionCrons: 1), now: now)
    #expect(tracker.reportsBySessionID == [
        "abc": BackgroundWorkReport(backgroundTasks: 0, sessionCrons: 1, epoch: 1000),
    ])
}

@Test func zeroCountStopClearsReport() {
    var tracker = BackgroundWorkTracker()
    tracker.apply(stop(backgroundTasks: 3, sessionCrons: 1), now: now)
    tracker.apply(stop(backgroundTasks: 0, sessionCrons: 0), now: Date(timeIntervalSince1970: 2000))
    #expect(tracker.reportsBySessionID.isEmpty)
}

/// Pre-v2.1.145 CLIs (and payload-less stops) omit the arrays entirely; both
/// mean "no background work left", so the report clears rather than lingers.
@Test func stopOmittingCountsClearsReport() {
    var tracker = BackgroundWorkTracker()
    tracker.apply(stop(backgroundTasks: 3, sessionCrons: 1), now: now)
    tracker.apply(stop(), now: Date(timeIntervalSince1970: 2000))
    #expect(tracker.reportsBySessionID.isEmpty)
}

/// Background jobs survive new turns — the exact reason the transcript alone
/// cannot see them — so a fresh prompt must not erase the report.
@Test func userPromptSubmitDoesNotClearReport() {
    var tracker = BackgroundWorkTracker()
    tracker.apply(stop(backgroundTasks: 1, sessionCrons: 0), now: now)
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "UserPromptSubmit"), now: Date(timeIntervalSince1970: 2000))
    #expect(tracker.reportsBySessionID == [
        "abc": BackgroundWorkReport(backgroundTasks: 1, sessionCrons: 0, epoch: 1000),
    ])
}

@Test(arguments: ["Notification", "PreToolUse", "UserPromptSubmit", ""])
func nonStopHookEventsRecordNothing(hookEvent: String) {
    var tracker = BackgroundWorkTracker()
    tracker.apply(stop(hookEvent: hookEvent, backgroundTasks: 2, sessionCrons: 1), now: now)
    #expect(tracker.reportsBySessionID.isEmpty)
}

@Test func stopWithoutSessionIDIsIgnored() {
    var tracker = BackgroundWorkTracker()
    tracker.apply(stop(nil, backgroundTasks: 2, sessionCrons: 1), now: now)
    #expect(tracker.reportsBySessionID.isEmpty)
}

@Test func latestStopReportWins() {
    var tracker = BackgroundWorkTracker()
    tracker.apply(stop(backgroundTasks: 3, sessionCrons: 0), now: now)
    tracker.apply(stop(backgroundTasks: 1, sessionCrons: 2), now: Date(timeIntervalSince1970: 5000))
    #expect(tracker.reportsBySessionID == [
        "abc": BackgroundWorkReport(backgroundTasks: 1, sessionCrons: 2, epoch: 5000),
    ])
}

@Test func reportsMapSessionIDsToTranscriptPathsByStem() {
    var tracker = BackgroundWorkTracker()
    tracker.apply(stop("abc-123", backgroundTasks: 1, sessionCrons: 0), now: now)
    tracker.apply(stop("orphan", backgroundTasks: 1, sessionCrons: 0), now: now)
    let reports = tracker.reports(forPaths: [
        "/home/u/.claude/projects/p/abc-123.jsonl",
        "/home/u/.claude/projects/p/other.jsonl",
    ])
    #expect(reports == [
        "/home/u/.claude/projects/p/abc-123.jsonl":
            BackgroundWorkReport(backgroundTasks: 1, sessionCrons: 0, epoch: 1000),
    ])
}
