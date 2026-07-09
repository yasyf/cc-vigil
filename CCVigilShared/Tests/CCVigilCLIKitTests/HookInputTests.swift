import CCVigilCLIKit
import CCVigilShared
import Foundation
import Testing

@Test func extractsAllHookFields() throws {
    let json = #"{"session_id":"s1","hook_event_name":"Notification","notification_type":"permission_request"}"#
    let payload = try HookInput.nudgePayload(fromHookJSON: Data(json.utf8), claudePid: 42)
    #expect(payload == NudgePayload(
        sessionId: "s1",
        hookEvent: "Notification",
        notificationKind: "permission_request",
        claudePid: 42
    ))
}

@Test func missingFieldsBecomeNil() throws {
    let payload = try HookInput.nudgePayload(fromHookJSON: Data("{}".utf8), claudePid: nil)
    #expect(payload == NudgePayload())
}

@Test func wrongTypedFieldsBecomeNil() throws {
    let json = #"{"session_id":5,"hook_event_name":"Stop","background_tasks":7,"session_crons":"hourly"}"#
    let payload = try HookInput.nudgePayload(fromHookJSON: Data(json.utf8), claudePid: nil)
    #expect(payload == NudgePayload(hookEvent: "Stop"))
}

/// A captured Claude Code v2.1.145+ Stop payload: `background_tasks` and
/// `session_crons` arrive as arrays of task objects and are forwarded as counts.
@Test func extractsBackgroundWorkCountsFromStopPayload() throws {
    let json = #"""
    {"session_id":"a1b2","transcript_path":"/t/a1b2.jsonl","hook_event_name":"Stop","stop_hook_active":false,
     "background_tasks":[
        {"id":"bash_1","type":"shell","status":"running","command":"cargo build --release"},
        {"id":"agent_2","type":"subagent","status":"running","agent_type":"general-purpose"}],
     "session_crons":[{"id":"cron_1","schedule":"*/5 * * * *","prompt":"poll CI"}]}
    """#
    let payload = try HookInput.nudgePayload(fromHookJSON: Data(json.utf8), claudePid: 7)
    #expect(payload == NudgePayload(
        sessionId: "a1b2",
        hookEvent: "Stop",
        claudePid: 7,
        backgroundTasks: 2,
        sessionCrons: 1
    ))
}

@Test func emptyBackgroundWorkArraysBecomeZeroCounts() throws {
    let json = #"{"session_id":"s1","hook_event_name":"Stop","background_tasks":[],"session_crons":[]}"#
    let payload = try HookInput.nudgePayload(fromHookJSON: Data(json.utf8), claudePid: nil)
    #expect(payload == NudgePayload(sessionId: "s1", hookEvent: "Stop", backgroundTasks: 0, sessionCrons: 0))
}

@Test func rejectsNonJSONInput() {
    #expect(throws: HookInputError.notJSON) {
        try HookInput.nudgePayload(fromHookJSON: Data("not json".utf8), claudePid: nil)
    }
}

@Test func rejectsNonObjectRoot() {
    #expect(throws: HookInputError.notObject) {
        try HookInput.nudgePayload(fromHookJSON: Data("[1,2]".utf8), claudePid: nil)
    }
}
