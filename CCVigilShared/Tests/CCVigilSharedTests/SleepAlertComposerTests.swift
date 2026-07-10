import CCVigilShared
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_767_000_000)
private let atEpoch = Int64(now.timeIntervalSince1970)

private func report(
    shouldBlock: Bool = false,
    blockApplied: Bool = false,
    activeSessions: [ActiveSession] = [],
    holds: [Hold] = [],
    latchedCutouts: [CutoutKind] = [],
    pausedUntil: Date? = nil
) -> StatusReport {
    StatusReport(
        shouldBlock: shouldBlock,
        blockApplied: blockApplied,
        helper: .reachable,
        activeSessions: activeSessions,
        holds: holds,
        latchedCutouts: latchedCutouts,
        pausedUntil: pausedUntil
    )
}

private let session = ActiveSession(
    path: "/Users/ada/.claude/projects/-Users-ada-Code-cc-vigil/0195aabb-1111-2222-3333-444455556666.jsonl",
    reasons: [.recentActivity, .midTool]
)

private let hold = Hold(
    key: "app-12ab34cd",
    reason: "menu hold",
    ttlSeconds: 1800,
    createdAt: now,
    pid: nil
)

private func alerts(_ reports: [StatusReport]) -> [[SleepAlert]] {
    var composer = SleepAlertComposer()
    return reports.map { composer.ingest($0, now: now) }
}

@Test func firstReportNeverEmits() {
    #expect(alerts([report()]) == [[]])
    #expect(alerts([report(shouldBlock: true, blockApplied: true)]) == [[]])
}

@Test func releaseFiresOnceWhenAgentsFinish() {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session], holds: [hold]),
        report(),
        report(),
    ])
    #expect(results == [
        [],
        [SleepAlert(id: 1, atEpoch: atEpoch, payload: .released(sessions: 1, holds: 1))],
        [],
    ])
}

@Test func releaseNamesTheLastBlockingSnapshotAcrossAnAppliedIntermediate() {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session, session], holds: [hold]),
        report(shouldBlock: false, blockApplied: true),
        report(),
    ])
    #expect(results[1] == [])
    #expect(results[2] == [SleepAlert(id: 1, atEpoch: atEpoch, payload: .released(sessions: 2, holds: 1))])
}

@Test(arguments: [
    ([session], [hold], 1, 1),
    ([session, session], [Hold](), 2, 0),
    ([ActiveSession](), [hold, hold], 0, 2),
])
func releaseCountsWhatHadBeenHolding(
    sessions: [ActiveSession],
    holds: [Hold],
    expectedSessions: Int,
    expectedHolds: Int
) {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: sessions, holds: holds),
        report(),
    ])
    #expect(results[1] == [SleepAlert(
        id: 1,
        atEpoch: atEpoch,
        payload: .released(sessions: expectedSessions, holds: expectedHolds)
    )])
}

@Test func pauseDoesNotFireRelease() {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(pausedUntil: now.addingTimeInterval(3600)),
    ])
    #expect(results == [[], []])
}

@Test func helperCrashWithWorkStillPendingDoesNotFireRelease() {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: true, blockApplied: false, activeSessions: [session]),
    ])
    #expect(results == [[], []])
}

@Test(arguments: [
    ([session], [Hold]()),
    ([ActiveSession](), [hold]),
])
func releaseSuppressedByLingeringSessionsOrHolds(sessions: [ActiveSession], holds: [Hold]) {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session], holds: [hold]),
        report(shouldBlock: false, blockApplied: false, activeSessions: sessions, holds: holds),
    ])
    #expect(results == [[], []])
}

@Test func cutoutLatchFiresMidBlockAndSuppressesRelease() {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
    ])
    #expect(results == [
        [],
        [SleepAlert(id: 1, atEpoch: atEpoch, payload: .cutoutLatched(kinds: [.battery]))],
        [],
    ])
}

@Test func cutoutLatchNamesEveryNewlyLatchedKind() {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: false, blockApplied: false, latchedCutouts: [.thermal, .battery]),
    ])
    #expect(results[1] == [SleepAlert(
        id: 1,
        atEpoch: atEpoch,
        payload: .cutoutLatched(kinds: [.battery, .thermal])
    )])
}

@Test func cutoutLatchWhileIdleDoesNotFire() {
    let results = alerts([
        report(),
        report(latchedCutouts: [.battery]),
    ])
    #expect(results == [[], []])
}

@Test func cutoutSuppressedBlockSettlingDoesNotFireRelease() {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: false, blockApplied: true, activeSessions: [session], latchedCutouts: [.battery]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
    ])
    #expect(results == [
        [],
        [SleepAlert(id: 1, atEpoch: atEpoch, payload: .cutoutLatched(kinds: [.battery]))],
        [],
    ])
}

@Test func cutoutUnlatchReArmsAndFiresAgain() {
    let results = alerts([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
    ])
    #expect(results == [
        [],
        [SleepAlert(id: 1, atEpoch: atEpoch, payload: .cutoutLatched(kinds: [.battery]))],
        [],
        [SleepAlert(id: 2, atEpoch: atEpoch, payload: .cutoutLatched(kinds: [.battery]))],
    ])
}

@Test func idsAreMonotonicAcrossReleaseEdges() {
    let blocking = report(shouldBlock: true, blockApplied: true, activeSessions: [session])
    let idle = report()
    let results = alerts([blocking, idle, blocking, idle, blocking, idle])
    #expect(results == [
        [],
        [SleepAlert(id: 1, atEpoch: atEpoch, payload: .released(sessions: 1, holds: 0))],
        [],
        [SleepAlert(id: 2, atEpoch: atEpoch, payload: .released(sessions: 1, holds: 0))],
        [],
        [SleepAlert(id: 3, atEpoch: atEpoch, payload: .released(sessions: 1, holds: 0))],
    ])
}

@Test func restartResumesFromPersistedCounterWithoutIdReuse() {
    let prior = SleepAlert(id: 4, atEpoch: atEpoch, payload: .released(sessions: 2, holds: 0))
    var composer = SleepAlertComposer(nextAlertId: 5, recentAlerts: [prior])
    #expect(composer.ingest(report(shouldBlock: true, blockApplied: true, activeSessions: [session]), now: now) == [])
    let released = SleepAlert(id: 5, atEpoch: atEpoch, payload: .released(sessions: 1, holds: 0))
    #expect(composer.ingest(report(), now: now) == [released])
    #expect(composer.nextAlertId == 6)
    #expect(composer.recentAlerts == [prior, released])
}

@Test func recentAlertsRingIsBoundedToCap() {
    var composer = SleepAlertComposer(cap: 3)
    let blocking = report(shouldBlock: true, blockApplied: true, activeSessions: [session])
    let idle = report()
    for _ in 0 ..< 5 {
        _ = composer.ingest(blocking, now: now)
        _ = composer.ingest(idle, now: now)
    }
    #expect(composer.recentAlerts.map(\.id) == [3, 4, 5])
    #expect(composer.nextAlertId == 6)
}

@Test func seededAlertedCutoutDoesNotReAnnounceStillLatchedAcrossRestart() {
    var composer = SleepAlertComposer(alertedCutouts: [.battery])
    let stillLatched = report(
        shouldBlock: false,
        blockApplied: false,
        activeSessions: [session],
        latchedCutouts: [.battery]
    )
    #expect(composer.ingest(stillLatched, now: now) == [])
    #expect(composer.alertedCutouts == [.battery])
}

@Test func seededAlertedCutoutReArmsAfterUnlatch() {
    var composer = SleepAlertComposer(alertedCutouts: [.battery])
    let results = [
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
    ].map { composer.ingest($0, now: now) }
    #expect(results == [
        [],
        [],
        [SleepAlert(id: 1, atEpoch: atEpoch, payload: .cutoutLatched(kinds: [.battery]))],
    ])
}
