import CCVigilShared
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1000)

@Test func notificationHookRecordsWaitHint() {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification"), now: now)
    #expect(tracker.waitEpochsBySessionID == ["abc": 1000])
}

@Test func userPromptSubmitClearsWaitHint() {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification"), now: now)
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "UserPromptSubmit"), now: now)
    #expect(tracker.waitEpochsBySessionID.isEmpty)
}

@Test(arguments: ["Stop", "SubagentStop", "PreToolUse", ""])
func otherHookEventsLeaveHintsUntouched(hookEvent: String) {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification"), now: now)
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: hookEvent), now: Date(timeIntervalSince1970: 2000))
    tracker.apply(NudgePayload(sessionId: "xyz", hookEvent: hookEvent), now: Date(timeIntervalSince1970: 2000))
    #expect(tracker.waitEpochsBySessionID == ["abc": 1000])
}

@Test func nudgeWithoutSessionIDIsIgnored() {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(hookEvent: "Notification"), now: now)
    #expect(tracker.waitEpochsBySessionID.isEmpty)
}

@Test func latestNotificationWins() {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification"), now: now)
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification"), now: Date(timeIntervalSince1970: 5000))
    #expect(tracker.waitEpochsBySessionID == ["abc": 5000])
}

@Test func hintsMapSessionIDsToTranscriptPathsByStem() {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc-123", hookEvent: "Notification"), now: now)
    tracker.apply(NudgePayload(sessionId: "orphan", hookEvent: "Notification"), now: now)
    let hints = tracker.hints(forPaths: [
        "/home/u/.claude/projects/p/abc-123.jsonl",
        "/home/u/.claude/projects/p/other.jsonl",
    ])
    #expect(hints == ["/home/u/.claude/projects/p/abc-123.jsonl": 1000])
}
