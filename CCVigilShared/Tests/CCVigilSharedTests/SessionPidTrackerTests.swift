import CCVigilShared
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1000)

private func nudge(
    _ sessionID: String? = "abc",
    hookEvent: String? = "Notification",
    claudePid: Int32? = 4242
) -> NudgePayload {
    NudgePayload(sessionId: sessionID, hookEvent: hookEvent, claudePid: claudePid)
}

@Test func nudgeWithClaudePidRecordsTrackedPid() {
    var tracker = SessionPidTracker()
    tracker.apply(nudge(claudePid: 4242), now: now)
    #expect(tracker.pidsBySessionID == ["abc": TrackedPid(pid: 4242, capturedAtEpoch: 1000)])
}

/// The pid rides on whatever nudge Claude Code sent — apply keys on claudePid,
/// not on any particular hook, so every hook that carries the pid records it.
@Test(arguments: ["Notification", "Stop", "SubagentStop", "PreToolUse", "UserPromptSubmit", ""])
func anyHookEventCarryingPidIsTracked(hookEvent: String) {
    var tracker = SessionPidTracker()
    tracker.apply(nudge(hookEvent: hookEvent, claudePid: 4242), now: now)
    #expect(tracker.pidsBySessionID == ["abc": TrackedPid(pid: 4242, capturedAtEpoch: 1000)])
}

@Test func latestPidWins() {
    var tracker = SessionPidTracker()
    tracker.apply(nudge(claudePid: 100), now: now)
    tracker.apply(nudge(claudePid: 200), now: Date(timeIntervalSince1970: 5000))
    #expect(tracker.pidsBySessionID == ["abc": TrackedPid(pid: 200, capturedAtEpoch: 5000)])
}

@Test func nudgeWithoutClaudePidIsIgnored() {
    var tracker = SessionPidTracker()
    tracker.apply(nudge(claudePid: nil), now: now)
    #expect(tracker.pidsBySessionID.isEmpty)
}

/// A pid-less nudge carries no evidence about the process, so it leaves an
/// already-tracked pid in place rather than erasing it.
@Test func pidlessNudgeLeavesExistingPidUntouched() {
    var tracker = SessionPidTracker()
    tracker.apply(nudge(claudePid: 4242), now: now)
    tracker.apply(nudge(hookEvent: "UserPromptSubmit", claudePid: nil), now: Date(timeIntervalSince1970: 5000))
    #expect(tracker.pidsBySessionID == ["abc": TrackedPid(pid: 4242, capturedAtEpoch: 1000)])
}

@Test func pidNudgeWithoutSessionIDIsIgnored() {
    var tracker = SessionPidTracker()
    tracker.apply(nudge(nil, claudePid: 4242), now: now)
    #expect(tracker.pidsBySessionID.isEmpty)
}

@Test func pidsMapSessionIDsToTranscriptPathsByStem() {
    var tracker = SessionPidTracker()
    tracker.apply(nudge("abc-123", claudePid: 10), now: now)
    tracker.apply(nudge("orphan", claudePid: 20), now: now)
    let pids = tracker.pids(forPaths: [
        "/home/u/.claude/projects/p/abc-123.jsonl",
        "/home/u/.claude/projects/p/other.jsonl",
    ])
    #expect(pids == ["/home/u/.claude/projects/p/abc-123.jsonl": TrackedPid(pid: 10, capturedAtEpoch: 1000)])
}

/// The liveness defense mirrors HoldRegistry.restored: a session is live only
/// when its pid still resolves and the process did not start after we captured
/// the pid (a start strictly later than capture means the pid was reused by a
/// different process). Equality at the capture instant is ambiguous, and a sleep
/// inhibitor resolves ambiguity toward live — it must never sleep the Mac on it.
@Test(arguments: [
    ("live-started-earlier", Int64?(500), true),
    ("live-started-at-capture", Int64?(1000), true),
    ("dead-no-process", Int64?.none, false),
    ("ghost-reused-pid", Int64?(1500), false),
])
func livenessMatrix(label: String, processStartEpoch: Int64?, expectLive: Bool) {
    var tracker = SessionPidTracker()
    tracker.apply(nudge(label, claudePid: 4242), now: now)
    let live = tracker.liveSessionIDs { queried in
        #expect(queried == 4242)
        return processStartEpoch
    }
    #expect(live == (expectLive ? [label] : []))
}

@Test func liveSessionIDsReturnsOnlyResolvedNonGhostSessions() {
    var tracker = SessionPidTracker()
    tracker.apply(nudge("live", claudePid: 10), now: now)
    tracker.apply(nudge("dead", claudePid: 20), now: now)
    tracker.apply(nudge("ghost", claudePid: 30), now: now)
    let starts: [Int32: Int64] = [10: 500, 30: 1500]
    let live = tracker.liveSessionIDs { starts[$0] }
    #expect(live == ["live"])
}

/// Eviction reclaims entries the map would otherwise hold forever: a session
/// whose process is no longer live (a vanished pid or a recycled ghost) and whose
/// capture predates the discovery window can never pin a transcript again, so it
/// is dropped and reverts to unmapped cliff behavior. A live session is kept
/// regardless of age — its long-running process is exactly what the pin protects
/// — and a recently-captured entry is kept even when dead, so a just-ended
/// session is not evicted before the window would have dropped its transcript.
@Test func pruneEvictsNonLiveEntriesOlderThanCutoffButKeepsLiveAndRecent() {
    var tracker = SessionPidTracker()
    tracker.apply(nudge("dead-old", claudePid: 10), now: Date(timeIntervalSince1970: 1000))
    tracker.apply(nudge("live-old", claudePid: 20), now: Date(timeIntervalSince1970: 1000))
    tracker.apply(nudge("ghost-old", claudePid: 30), now: Date(timeIntervalSince1970: 1000))
    tracker.apply(nudge("dead-recent", claudePid: 40), now: Date(timeIntervalSince1970: 9000))

    let starts: [Int32: Int64] = [20: 500, 30: 5000]
    tracker.prune(capturedBefore: 5000) { starts[$0] }

    #expect(tracker.pidsBySessionID == [
        "live-old": TrackedPid(pid: 20, capturedAtEpoch: 1000),
        "dead-recent": TrackedPid(pid: 40, capturedAtEpoch: 9000),
    ])
}
