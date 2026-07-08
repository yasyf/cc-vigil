import CCVigilAppKit
import CCVigilShared
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_767_000_000)

private func report(
    shouldBlock: Bool = false,
    blockApplied: Bool = false,
    helper: HelperLink = .reachable,
    activeSessions: [ActiveSession] = [],
    holds: [Hold] = [],
    latchedCutouts: [CutoutKind] = [],
    pausedUntil: Date? = nil
) -> StatusReport {
    StatusReport(
        shouldBlock: shouldBlock,
        blockApplied: blockApplied,
        helper: helper,
        activeSessions: activeSessions,
        holds: holds,
        latchedCutouts: latchedCutouts,
        pausedUntil: pausedUntil
    )
}

private func model(_ report: StatusReport?) -> StatusViewModel {
    var model = StatusViewModel()
    if let report {
        model.apply(.statusUpdated(report))
    }
    return model
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

@Test func startsDisconnected() {
    let model = StatusViewModel()
    #expect(model.icon == .disconnected)
    #expect(model.headline(now: now) == "daemon unreachable")
    #expect(model.canSendCommands == false)
    #expect(model.sessionLines == [])
}

@Test func disconnectDropsTheStaleReport() {
    var model = model(report(shouldBlock: true, blockApplied: true))
    model.apply(.disconnected)
    #expect(model.icon == .disconnected)
    #expect(model.report == nil)
}

@Test(arguments: [
    (report(), MenuIcon.idle),
    (report(shouldBlock: true, blockApplied: true), MenuIcon.blocking),
    (report(shouldBlock: true, blockApplied: false), MenuIcon.blocking),
    (report(shouldBlock: false, blockApplied: true), MenuIcon.blocking),
    (report(pausedUntil: now.addingTimeInterval(600)), MenuIcon.paused),
    (report(latchedCutouts: [.battery]), MenuIcon.latched),
    (
        report(
            shouldBlock: true,
            blockApplied: true,
            latchedCutouts: [.thermal],
            pausedUntil: now.addingTimeInterval(600)
        ),
        MenuIcon.latched
    ),
    (
        report(shouldBlock: true, blockApplied: true, pausedUntil: now.addingTimeInterval(600)),
        MenuIcon.paused
    ),
])
func iconReflectsReportWithLatchedThenPausedPriority(input: StatusReport, expected: MenuIcon) {
    #expect(model(input).icon == expected)
}

@Test(arguments: [
    (report(), "idle — sleep not blocked"),
    (
        report(shouldBlock: true, blockApplied: true, activeSessions: [session]),
        "keeping the Mac awake — 1 active session"
    ),
    (
        report(shouldBlock: true, blockApplied: false, activeSessions: [session, session], holds: [hold]),
        "keeping the Mac awake (not yet applied) — 2 active sessions, 1 hold"
    ),
    (
        report(shouldBlock: true, blockApplied: true),
        "keeping the Mac awake — settling"
    ),
    (report(blockApplied: true), "releasing the sleep block"),
    (
        report(pausedUntil: now.addingTimeInterval(5400)),
        "paused — 1h30m left"
    ),
    (
        report(shouldBlock: true, latchedCutouts: [.battery, .thermal]),
        "cutout latched: battery, thermal"
    ),
])
func headlineIsExact(input: StatusReport, expected: String) {
    #expect(model(input).headline(now: now) == expected)
}

@Test func sessionLinesNameProjectAndShortId() {
    let model = model(report(shouldBlock: true, blockApplied: true, activeSessions: [session]))
    #expect(model.sessionLines == [
        "Users-ada-Code-cc-vigil · 0195aabb — recent-activity, mid-tool",
    ])
}

@Test func holdLinesShowRemainingTime() {
    let model = model(report(shouldBlock: true, blockApplied: true, holds: [hold]))
    #expect(model.holdLines(now: now.addingTimeInterval(60)) == [
        "app-12ab34cd — menu hold (29m left)",
    ])
}

@Test func pauseActionTogglesOnPausedUntil() {
    #expect(model(report()).pauseAction == .pause)
    #expect(model(report(pausedUntil: now)).pauseAction == .resume)
}

@Test func activeHoldsComeFromTheReport() {
    #expect(model(report(holds: [hold])).activeHolds == [hold])
    #expect(StatusViewModel().activeHolds == [])
}

@Test(arguments: [
    (MenuIcon.disconnected, "eye.slash"),
    (MenuIcon.idle, "eye"),
    (MenuIcon.blocking, "eye.fill"),
    (MenuIcon.latched, "exclamationmark.triangle.fill"),
    (MenuIcon.paused, "pause.circle.fill"),
])
func iconsMapToDistinctSymbols(icon: MenuIcon, expected: String) {
    #expect(icon.systemImage == expected)
}

@Test func sessionDisplayKeepsUnprefixedProjectNames() {
    #expect(SessionDisplay.name(forTranscriptPath: "/tmp/proj/abcdef1234.jsonl") == "proj · abcdef12")
}
