import CCVigilCLIKit
import CCVigilShared
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func rendersQuietStatus() {
    let report = StatusReport(
        shouldBlock: false,
        blockApplied: false,
        helper: .unknown,
        activeSessions: [],
        holds: [],
        latchedCutouts: [],
        pausedUntil: nil
    )
    let expected = """
    blocking: no
    helper: unknown
    paused: no
    cutouts: (none)
    sessions: (none)
    holds: (none)
    """
    #expect(StatusRenderer.render(report, now: now) == expected)
}

@Test func rendersBusyStatus() {
    let report = StatusReport(
        shouldBlock: true,
        blockApplied: true,
        helper: .reachable,
        activeSessions: [ActiveSession(path: "/t/a.jsonl", reasons: [.recentActivity, .midTool])],
        holds: [Hold(
            key: "bake",
            reason: "long deploy",
            ttlSeconds: 3600,
            createdAt: now.addingTimeInterval(-60),
            pid: nil
        )],
        latchedCutouts: [.battery, .thermal],
        pausedUntil: now.addingTimeInterval(600)
    )
    let expected = """
    blocking: yes (applied)
    helper: reachable
    paused: until 2027-01-15T08:10:00Z
    cutouts: battery, thermal
    sessions:
      /t/a.jsonl — recent-activity, mid-tool
    holds:
      bake — long deploy (expires in 59m)
    """
    #expect(StatusRenderer.render(report, now: now) == expected)
}

@Test(arguments: [
    (true, false, "yes (not yet applied)"),
    (false, true, "no (still applied)"),
])
func rendersUnsettledBlockingStates(shouldBlock: Bool, applied: Bool, expected: String) {
    let report = StatusReport(
        shouldBlock: shouldBlock,
        blockApplied: applied,
        helper: .unreachable,
        activeSessions: [],
        holds: [],
        latchedCutouts: [],
        pausedUntil: nil
    )
    #expect(StatusRenderer.render(report, now: now).hasPrefix("blocking: \(expected)\nhelper: unreachable"))
}

@Test func rendersDeterministicJSON() throws {
    let report = StatusReport(
        shouldBlock: false,
        blockApplied: false,
        helper: .dryRun,
        activeSessions: [],
        holds: [],
        latchedCutouts: [],
        pausedUntil: nil
    )
    let expected = #"{"activeSessions":[],"blockApplied":false,"helper":"dry-run","#
        + #""holds":[],"latchedCutouts":[],"shouldBlock":false}"#
    #expect(try StatusRenderer.renderJSON(report) == expected)
}
