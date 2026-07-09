import CCVigilAppKit
import CCVigilShared
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_767_000_000)
private let releasedAt = now.formatted(date: .omitted, time: .shortened)

private extension NotificationSettings {
    static let both = NotificationSettings(notifyOnRelease: true, notifyOnCutout: true)
}

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

private func notifications(
    _ reports: [StatusReport?],
    settings: NotificationSettings = .both
) -> [[SleepNotification]] {
    var notifier = SleepNotifier()
    return reports.map { report in
        let event: StatusViewModel.Event = report.map { .statusUpdated($0) } ?? .disconnected
        return notifier.detect(event, settings: settings, now: now)
    }
}

@Test func firstReportNeverFires() {
    #expect(notifications([report()]) == [[]])
    #expect(notifications([report(shouldBlock: true, blockApplied: true)]) == [[]])
}

@Test func releaseFiresOnceWhenAgentsFinish() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session], holds: [hold]),
        report(),
        report(),
    ])
    #expect(results == [
        [],
        [SleepNotification(
            kind: .released,
            title: "Agents finished",
            body: "The Mac may sleep now — 1 active session and 1 hold finished at \(releasedAt)."
        )],
        [],
    ])
}

@Test func releaseNamesTheLastBlockingSnapshotAcrossAnAppliedIntermediate() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session, session], holds: [hold]),
        report(shouldBlock: false, blockApplied: true),
        report(),
    ])
    #expect(results[2] == [SleepNotification(
        kind: .released,
        title: "Agents finished",
        body: "The Mac may sleep now — 2 active sessions and 1 hold finished at \(releasedAt)."
    )])
    #expect(results[1] == [])
}

@Test(arguments: [
    ([session], [hold], "1 active session and 1 hold"),
    ([session, session], [Hold](), "2 active sessions"),
    ([ActiveSession](), [hold, hold], "2 holds"),
])
func releaseBodyCountsWhatHadBeenHolding(
    sessions: [ActiveSession],
    holds: [Hold],
    summary: String
) {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: sessions, holds: holds),
        report(),
    ])
    #expect(results[1] == [SleepNotification(
        kind: .released,
        title: "Agents finished",
        body: "The Mac may sleep now — \(summary) finished at \(releasedAt)."
    )])
}

@Test func pauseDoesNotFireRelease() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(pausedUntil: now.addingTimeInterval(3600)),
    ])
    #expect(results == [[], []])
}

@Test func helperCrashWithWorkStillPendingDoesNotFireRelease() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: true, blockApplied: false, activeSessions: [session]),
    ])
    #expect(results == [[], []])
}

@Test func cutoutLatchFiresMidBlockAndSuppressesRelease() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
    ])
    #expect(results == [
        [],
        [SleepNotification(
            kind: .cutoutLatched,
            title: "Sleep protection dropped",
            body: "Battery cutout latched — the Mac may sleep despite active agents."
        )],
        [],
    ])
}

@Test func cutoutLatchNamesEveryNewlyLatchedKind() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: false, blockApplied: false, latchedCutouts: [.thermal, .battery]),
    ])
    #expect(results[1] == [SleepNotification(
        kind: .cutoutLatched,
        title: "Sleep protection dropped",
        body: "Battery and thermal cutouts latched — the Mac may sleep despite active agents."
    )])
}

@Test func cutoutLatchWhileIdleDoesNotFire() {
    let results = notifications([
        report(),
        report(latchedCutouts: [.battery]),
    ])
    #expect(results == [[], []])
}

@Test func releaseToggleSuppressesTheReleaseEdge() {
    let results = notifications(
        [
            report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
            report(),
        ],
        settings: NotificationSettings(notifyOnRelease: false, notifyOnCutout: true)
    )
    #expect(results == [[], []])
}

@Test func cutoutToggleSuppressesTheCutoutEdge() {
    let results = notifications(
        [
            report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
            report(shouldBlock: false, blockApplied: false, latchedCutouts: [.battery]),
        ],
        settings: NotificationSettings(notifyOnRelease: true, notifyOnCutout: false)
    )
    #expect(results == [[], []])
}

@Test func disconnectResetsSoAReconnectedIdleReportDoesNotFire() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        nil,
        report(),
    ])
    #expect(results == [[], [], []])
}

@Test func cutoutSuppressedBlockSettlingDoesNotFireRelease() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        report(shouldBlock: false, blockApplied: true, activeSessions: [session], latchedCutouts: [.battery]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
    ])
    #expect(results == [
        [],
        [SleepNotification(
            kind: .cutoutLatched,
            title: "Sleep protection dropped",
            body: "Battery cutout latched — the Mac may sleep despite active agents."
        )],
        [],
    ])
}

@Test func cutoutLatchedWhileDisconnectedFiresOnReconnect() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        nil,
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
    ])
    #expect(results == [
        [],
        [],
        [SleepNotification(
            kind: .cutoutLatched,
            title: "Sleep protection dropped",
            body: "Battery cutout latched — the Mac may sleep despite active agents."
        )],
        [],
    ])
}

@Test func idleThenReconnectWithLatchedCutoutDoesNotFireFromStaleHistory() {
    let results = notifications(
        [
            report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
            report(),
            nil,
            report(latchedCutouts: [.battery]),
        ],
        settings: NotificationSettings(notifyOnRelease: false, notifyOnCutout: true)
    )
    #expect(results == [[], [], [], []])
}

@Test func settlingFirstSnapshotOnReconnectFiresCutoutExactlyOnce() {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        nil,
        report(shouldBlock: false, blockApplied: true, activeSessions: [session], latchedCutouts: [.battery]),
        report(shouldBlock: false, blockApplied: false, activeSessions: [session], latchedCutouts: [.battery]),
    ])
    #expect(results == [
        [],
        [],
        [SleepNotification(
            kind: .cutoutLatched,
            title: "Sleep protection dropped",
            body: "Battery cutout latched — the Mac may sleep despite active agents."
        )],
        [],
    ])
}

@Test(arguments: [
    ([session], [Hold]()),
    ([ActiveSession](), [hold]),
])
func releaseSuppressedIndependentlyByLingeringSessionsOrHolds(
    sessions: [ActiveSession],
    holds: [Hold]
) {
    let results = notifications([
        report(shouldBlock: true, blockApplied: true, activeSessions: [session], holds: [hold]),
        report(shouldBlock: false, blockApplied: false, activeSessions: sessions, holds: holds),
    ])
    #expect(results == [[], []])
}
