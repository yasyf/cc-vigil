import CCVigilShared
import Foundation
import Testing

private let now: Int64 = 1_800_000_000
private let clock = FixedClock(epoch: now)
private let path = "/t/session.jsonl"

private func idleProbe(lastEventEpoch: Int64) -> SessionProbe {
    SessionProbe(
        sessionPath: path,
        isWaiting: false,
        midTool: false,
        lastEventEpoch: lastEventEpoch,
        pending: []
    )
}

private func decide(
    _ sessions: [SessionProbe],
    hints: [String: Int64] = [:],
    backgroundWork: [String: BackgroundWorkReport] = [:]
) -> BlockDecision {
    OracleState(
        sessions: sessions,
        humanWaitHints: hints,
        backgroundWork: backgroundWork,
        sessionPids: [:],
        claudeProcessesAlive: true
    )
    .decision(config: .default, clock: clock, processStart: { _ in nil })
}

/// H2: a Stop hook reported live background work, then the transcript went
/// quiet across a turn boundary and Claude Code fired its idle Notification.
/// Nothing in the transcript is pending, yet the session is machine-driven —
/// the hint must not discount it and the report alone holds the block.
@Test func oracleBackgroundWorkReportHoldsIdleSessionDespiteHumanWaitHint() {
    let report = BackgroundWorkReport(backgroundTasks: 1, sessionCrons: 0, epoch: now - 100)
    let decision = decide(
        [idleProbe(lastEventEpoch: now - 4000)],
        hints: [path: now],
        backgroundWork: [path: report]
    )
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: path, reasons: [.backgroundWork])],
        discounts: []
    ))
}

@Test func oracleCronOnlyReportHoldsSession() {
    let report = BackgroundWorkReport(backgroundTasks: 0, sessionCrons: 2, epoch: now - 100)
    let decision = decide(
        [idleProbe(lastEventEpoch: now - 4000)],
        backgroundWork: [path: report]
    )
    #expect(decision.activeSessions == [ActiveSession(path: path, reasons: [.backgroundWork])])
}

@Test func oracleBackgroundWorkComposesAfterOtherReasons() {
    let report = BackgroundWorkReport(backgroundTasks: 1, sessionCrons: 0, epoch: now - 100)
    let decision = decide(
        [idleProbe(lastEventEpoch: now - 10)],
        backgroundWork: [path: report]
    )
    #expect(decision.activeSessions == [
        ActiveSession(path: path, reasons: [.recentActivity, .backgroundWork]),
    ])
}

/// The full cross-turn lifecycle, tracker included: a Stop reporting a
/// background task pins the idle session awake through a new turn and the
/// idle hint; the next Stop reporting none releases it back to the hint.
@Test func oracleBackgroundWorkLifecycleAcrossStops() {
    let probe = idleProbe(lastEventEpoch: now - 4000)
    func decideNow(_ tracker: BackgroundWorkTracker) -> BlockDecision {
        decide([probe], hints: [path: now], backgroundWork: tracker.reports(forPaths: [path]))
    }
    var tracker = BackgroundWorkTracker()
    tracker.apply(
        NudgePayload(sessionId: "session", hookEvent: "Stop", backgroundTasks: 1, sessionCrons: 0),
        now: Date(timeIntervalSince1970: TimeInterval(now - 100))
    )
    #expect(decideNow(tracker) == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: path, reasons: [.backgroundWork])],
        discounts: []
    ))

    tracker.apply(
        NudgePayload(sessionId: "session", hookEvent: "UserPromptSubmit"),
        now: Date(timeIntervalSince1970: TimeInterval(now - 50))
    )
    #expect(decideNow(tracker).shouldBlock == true)

    tracker.apply(
        NudgePayload(sessionId: "session", hookEvent: "Stop", backgroundTasks: 0, sessionCrons: 0),
        now: Date(timeIntervalSince1970: TimeInterval(now - 10))
    )
    let released = decideNow(tracker)
    #expect(released.shouldBlock == false)
    #expect(released.activeSessions.isEmpty)
    #expect(released.discounts == [SessionDiscount(path: path, reason: .humanWaitHint)])
}

/// A never-cleared report cannot pin the block forever: the pending-async
/// max-age cliff bounds it by its own epoch, not the transcript's.
@Test(arguments: [
    (Int64(43200), true),
    (Int64(43201), false),
])
func oracleBackgroundWorkCliffBoundary(reportAge: Int64, expectActive: Bool) {
    let report = BackgroundWorkReport(backgroundTasks: 1, sessionCrons: 1, epoch: now - reportAge)
    let decision = decide(
        [idleProbe(lastEventEpoch: now - 90000)],
        backgroundWork: [path: report]
    )
    #expect(decision.shouldBlock == expectActive)
    if expectActive {
        #expect(decision.activeSessions == [ActiveSession(path: path, reasons: [.backgroundWork])])
    } else {
        #expect(decision.activeSessions.isEmpty)
        #expect(decision.discounts.isEmpty)
    }
}

@Test func oracleStaleBackgroundWorkReportNoLongerBlocksHintDiscount() {
    let report = BackgroundWorkReport(backgroundTasks: 1, sessionCrons: 0, epoch: now - 50000)
    let decision = decide(
        [idleProbe(lastEventEpoch: now - 4000)],
        hints: [path: now],
        backgroundWork: [path: report]
    )
    #expect(decision.shouldBlock == false)
    #expect(decision.discounts == [SessionDiscount(path: path, reason: .humanWaitHint)])
}
