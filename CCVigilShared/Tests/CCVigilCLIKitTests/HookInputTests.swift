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
    let json = #"{"session_id":5,"hook_event_name":"Stop"}"#
    let payload = try HookInput.nudgePayload(fromHookJSON: Data(json.utf8), claudePid: nil)
    #expect(payload == NudgePayload(hookEvent: "Stop"))
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
