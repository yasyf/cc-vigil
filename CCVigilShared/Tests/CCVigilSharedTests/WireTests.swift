import CCVigilShared
import Foundation
import Testing

private func json(of request: WireRequest) throws -> String {
    try #require(String(bytes: WireCodec.encodePayload(request), encoding: .utf8))
}

private func json(of response: WireResponse) throws -> String {
    try #require(String(bytes: WireCodec.encodePayload(response), encoding: .utf8))
}

private func request(fromJSON json: String) throws -> WireRequest? {
    try WireCodec.decodePayload(WireRequest.self, from: Data(json.utf8))
}

@Test func requestJSONShapes() throws {
    let fullNudge = WireRequest.nudge(NudgePayload(
        sessionId: "s1",
        hookEvent: "Stop",
        notificationKind: "permission",
        claudePid: 123,
        backgroundTasks: 2,
        sessionCrons: 1,
        transcriptsRoot: "/relocated/.claude/projects"
    ))
    let expectations: [(WireRequest, String)] = [
        (
            fullNudge,
            #"{"backgroundTasks":2,"claudePid":123,"hookEvent":"Stop","notificationKind":"permission","#
                + #""op":"nudge","sessionCrons":1,"sessionId":"s1","transcriptsRoot":"/relocated/.claude/projects"}"#
        ),
        (.nudge(NudgePayload()), #"{"op":"nudge"}"#),
        (.status, #"{"op":"status"}"#),
        (
            .hold(key: "deploy", reason: "long deploy", ttlSeconds: 600, pid: 42),
            #"{"key":"deploy","op":"hold","pid":42,"reason":"long deploy","ttlSeconds":600}"#
        ),
        (
            .hold(key: "deploy", reason: "r", ttlSeconds: 600, pid: nil),
            #"{"key":"deploy","op":"hold","reason":"r","ttlSeconds":600}"#
        ),
        (.release(key: "deploy"), #"{"key":"deploy","op":"release"}"#),
        (.pause(seconds: 300), #"{"op":"pause","seconds":300}"#),
        (.clear, #"{"op":"clear"}"#),
        (.ping, #"{"op":"ping"}"#),
    ]
    for (request, expected) in expectations {
        #expect(try json(of: request) == expected)
    }
}

@Test(arguments: [
    WireRequest.nudge(NudgePayload(sessionId: "s1", hookEvent: "Stop", notificationKind: "idle", claudePid: 9)),
    .nudge(NudgePayload(sessionId: "s1", hookEvent: "Stop", claudePid: 9, backgroundTasks: 3, sessionCrons: 2)),
    .nudge(NudgePayload(sessionId: "s1", transcriptsRoot: "/relocated/.claude/projects")),
    .nudge(NudgePayload()),
    .status,
    .hold(key: "k", reason: "r", ttlSeconds: 600, pid: 42),
    .hold(key: "k", reason: "r", ttlSeconds: 600, pid: nil),
    .release(key: "k"),
    .pause(seconds: 300),
    .clear,
    .ping,
])
func requestRoundTripsThroughPayload(request: WireRequest) throws {
    let payload = try WireCodec.encodePayload(request)
    #expect(try WireCodec.decodePayload(WireRequest.self, from: payload) == request)
}

@Test func requestDecodeRejectsUnknownOp() throws {
    #expect(throws: DecodingError.self) {
        try WireCodec.decodePayload(WireRequest.self, from: Data(#"{"op":"reboot"}"#.utf8))
    }
}

@Test func requestDecodesFromLiteralJSON() throws {
    let decoded = try request(fromJSON: #"{"op":"nudge","sessionId":"abc","claudePid":7}"#)
    #expect(decoded == .nudge(NudgePayload(sessionId: "abc", claudePid: 7)))
}

@Test func responseJSONShapes() throws {
    #expect(try json(of: .ok) == #"{"result":"ok"}"#)
    #expect(try json(of: .error(message: "boom")) == #"{"message":"boom","result":"error"}"#)
    let report = StatusReport(
        shouldBlock: true,
        blockApplied: true,
        helper: .dryRun,
        activeSessions: [ActiveSession(path: "/t/s.jsonl", reasons: [.recentActivity, .waiting])],
        holds: [Hold(
            key: "k",
            reason: "r",
            ttlSeconds: 600,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            pid: nil
        )],
        latchedCutouts: [.battery],
        pausedUntil: nil
    )
    let expected = #"{"result":"status","status":{"activeSessions":[{"path":"/t/s.jsonl","#
        + #""reasons":["recent-activity","waiting"]}],"blockApplied":true,"helper":"dry-run","#
        + #""holds":[{"createdAt":1800000000,"#
        + #""key":"k","reason":"r","ttlSeconds":600}],"latchedCutouts":["battery"],"shouldBlock":true}}"#
    #expect(try json(of: .status(report)) == expected)
}

@Test func responseRoundTripsStatusReport() throws {
    let report = StatusReport(
        shouldBlock: false,
        blockApplied: false,
        helper: .reachable,
        activeSessions: [],
        holds: [Hold(
            key: "k",
            reason: "r",
            ttlSeconds: 600,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            pid: 42
        )],
        latchedCutouts: [.battery, .thermal],
        pausedUntil: Date(timeIntervalSince1970: 1_800_000_600)
    )
    let payload = try WireCodec.encodePayload(WireResponse.status(report))
    #expect(try WireCodec.decodePayload(WireResponse.self, from: payload) == .status(report))
}

@Test func statusReportWithoutAlertsOmitsTheKey() throws {
    let report = StatusReport(
        shouldBlock: false,
        blockApplied: false,
        helper: .reachable,
        activeSessions: [],
        holds: [],
        latchedCutouts: [],
        pausedUntil: nil
    )
    let encoded = try #require(String(bytes: WireCodec.encodePayload(report), encoding: .utf8))
    #expect(!encoded.contains("alerts"))
}

@Test func statusReportRejectsUnknownCutoutKind() throws {
    let json = #"{"activeSessions":[],"blockApplied":false,"helper":"reachable","#
        + #""holds":[],"latchedCutouts":["battery","teleport"],"shouldBlock":false}"#
    #expect(throws: DecodingError.self) {
        try WireCodec.decodePayload(StatusReport.self, from: Data(json.utf8))
    }
}

@Test func statusReportRoundTripsWithAlerts() throws {
    let report = StatusReport(
        shouldBlock: true,
        blockApplied: true,
        helper: .reachable,
        activeSessions: [],
        holds: [],
        latchedCutouts: [.battery],
        pausedUntil: nil,
        alerts: [
            SleepAlert(id: 1, atEpoch: 1_767_000_000, payload: .cutoutLatched(kinds: [.battery])),
            SleepAlert(id: 2, atEpoch: 1_767_000_050, payload: .released(sessions: 2, holds: 1)),
        ]
    )
    let payload = try WireCodec.encodePayload(WireResponse.status(report))
    #expect(try WireCodec.decodePayload(WireResponse.self, from: payload) == .status(report))
}
