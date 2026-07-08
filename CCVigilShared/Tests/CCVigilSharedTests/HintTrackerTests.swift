import CCVigilShared
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1000)

@Test func notificationHookRecordsWaitHint() {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification", notificationKind: "idle_prompt"), now: now)
    #expect(tracker.waitEpochsBySessionID == ["abc": 1000])
}

@Test func userPromptSubmitClearsWaitHint() {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification", notificationKind: "idle_prompt"), now: now)
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "UserPromptSubmit"), now: now)
    #expect(tracker.waitEpochsBySessionID.isEmpty)
}

@Test(arguments: ["Stop", "SubagentStop", "PreToolUse", ""])
func otherHookEventsLeaveHintsUntouched(hookEvent: String) {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification", notificationKind: "idle_prompt"), now: now)
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
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification", notificationKind: "idle_prompt"), now: now)
    tracker.apply(
        NudgePayload(sessionId: "abc", hookEvent: "Notification", notificationKind: "idle_prompt"),
        now: Date(timeIntervalSince1970: 5000)
    )
    #expect(tracker.waitEpochsBySessionID == ["abc": 5000])
}

@Test(arguments: [
    ("idle_prompt", true),
    ("permission_prompt", true),
    ("worker_permission_prompt", true),
    ("chrome_permission_prompt", true),
    ("workflow_permission_prompt", true),
    ("elicitation_dialog", true),
    ("agent_needs_input", true),
    ("auth_success", false),
    ("agent_completed", false),
    ("elicitation_complete", false),
    ("push_notification", false),
    ("computer_use_enter", false),
    ("some_unknown_kind", false),
])
func notificationKindGatesWaitHint(kind: String, recordsHint: Bool) {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification", notificationKind: kind), now: now)
    #expect(tracker.waitEpochsBySessionID == (recordsHint ? ["abc": 1000] : [:]))
}

@Test func nonHumanNotificationLeavesExistingHintUntouched() {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification", notificationKind: "idle_prompt"), now: now)
    tracker.apply(
        NudgePayload(sessionId: "abc", hookEvent: "Notification", notificationKind: "agent_completed"),
        now: Date(timeIntervalSince1970: 5000)
    )
    #expect(tracker.waitEpochsBySessionID == ["abc": 1000])
}

/// A sleep inhibitor fails toward staying awake: a nudge with no
/// notification_type (older CLI builds) records no hint, so the block persists.
@Test func missingNotificationKindRecordsNoHint() {
    var tracker = HintTracker()
    tracker.apply(NudgePayload(sessionId: "abc", hookEvent: "Notification", notificationKind: nil), now: now)
    #expect(tracker.waitEpochsBySessionID.isEmpty)
}

@Test func hintsMapSessionIDsToTranscriptPathsByStem() {
    var tracker = HintTracker()
    tracker.apply(
        NudgePayload(sessionId: "abc-123", hookEvent: "Notification", notificationKind: "idle_prompt"),
        now: now
    )
    tracker.apply(
        NudgePayload(sessionId: "orphan", hookEvent: "Notification", notificationKind: "idle_prompt"),
        now: now
    )
    let hints = tracker.hints(forPaths: [
        "/home/u/.claude/projects/p/abc-123.jsonl",
        "/home/u/.claude/projects/p/other.jsonl",
    ])
    #expect(hints == ["/home/u/.claude/projects/p/abc-123.jsonl": 1000])
}
