import CCVigilShared
import Foundation
import Testing

private func json(of request: WireRequest) throws -> String {
    let frame = try WireCodec.encodeFrame(request)
    return try #require(String(bytes: frame.dropFirst(WireFrame.headerBytes), encoding: .utf8))
}

private func json(of response: WireResponse) throws -> String {
    let frame = try WireCodec.encodeFrame(response)
    return try #require(String(bytes: frame.dropFirst(WireFrame.headerBytes), encoding: .utf8))
}

private func request(fromJSON json: String) throws -> WireRequest? {
    let frame = try WireFrame.encode(payload: Data(json.utf8))
    return try WireCodec.decodeFrame(WireRequest.self, from: frame)?.value
}

@Test func frameEncodesBigEndianLengthHeader() throws {
    let frame = try WireFrame.encode(payload: Data("hello".utf8))
    #expect(Array(frame.prefix(4)) == [0, 0, 0, 5])
    #expect(frame.count == 9)
}

@Test func frameRoundTrips() throws {
    let payload = Data("hello".utf8)
    let frame = try WireFrame.encode(payload: payload)
    let decoded = try #require(try WireFrame.decode(buffer: frame))
    #expect(decoded.payload == payload)
    #expect(decoded.consumed == 9)
}

@Test func frameEncodesEmptyPayload() throws {
    let frame = try WireFrame.encode(payload: Data())
    #expect(Array(frame) == [0, 0, 0, 0])
    let decoded = try #require(try WireFrame.decode(buffer: frame))
    #expect(decoded.payload.isEmpty)
    #expect(decoded.consumed == 4)
}

@Test(arguments: [0, 3, 4, 8])
func frameDecodeNeedsMoreBytes(available: Int) throws {
    let frame = try WireFrame.encode(payload: Data("hello".utf8))
    #expect(try WireFrame.decode(buffer: frame.prefix(available)) == nil)
}

@Test func frameDecodeLeavesTrailingBytes() throws {
    let first = try WireFrame.encode(payload: Data("one".utf8))
    let second = try WireFrame.encode(payload: Data("two".utf8))
    let buffer = first + second
    let decoded = try #require(try WireFrame.decode(buffer: buffer))
    #expect(decoded.payload == Data("one".utf8))
    #expect(decoded.consumed == first.count)
    let rest = try #require(try WireFrame.decode(buffer: buffer.dropFirst(decoded.consumed)))
    #expect(rest.payload == Data("two".utf8))
}

@Test func frameEncodeAcceptsExactlyTheCap() throws {
    let frame = try WireFrame.encode(payload: Data(count: WireFrame.maxPayloadBytes))
    #expect(frame.count == WireFrame.maxPayloadBytes + 4)
}

@Test func frameEncodeRejectsOversizePayload() {
    #expect(throws: WireError.payloadTooLarge(bytes: WireFrame.maxPayloadBytes + 1)) {
        try WireFrame.encode(payload: Data(count: WireFrame.maxPayloadBytes + 1))
    }
}

@Test func frameDecodeRejectsOversizeHeaderBeforeBuffering() {
    var buffer = Data()
    withUnsafeBytes(of: UInt32(WireFrame.maxPayloadBytes + 1).bigEndian) { buffer.append(contentsOf: $0) }
    #expect(throws: WireError.payloadTooLarge(bytes: WireFrame.maxPayloadBytes + 1)) {
        try WireFrame.decode(buffer: buffer)
    }
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
func requestRoundTripsThroughFrame(request: WireRequest) throws {
    let frame = try WireCodec.encodeFrame(request)
    let decoded = try #require(try WireCodec.decodeFrame(WireRequest.self, from: frame))
    #expect(decoded.value == request)
    #expect(decoded.consumed == frame.count)
}

@Test func requestDecodeRejectsUnknownOp() throws {
    let frame = try WireFrame.encode(payload: Data(#"{"op":"reboot"}"#.utf8))
    #expect(throws: DecodingError.self) {
        try WireCodec.decodeFrame(WireRequest.self, from: frame)
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
    let frame = try WireCodec.encodeFrame(WireResponse.status(report))
    let decoded = try #require(try WireCodec.decodeFrame(WireResponse.self, from: frame))
    #expect(decoded.value == .status(report))
}

private struct LegacyStatusReport: Codable, Equatable {
    let shouldBlock: Bool
    let blockApplied: Bool
    let helper: HelperLink
    let activeSessions: [ActiveSession]
    let holds: [Hold]
    let latchedCutouts: [CutoutKind]
    let pausedUntil: Date?
}

@Test func statusReportDecodesV0_2_0JSONWithoutAlertsKey() throws {
    let legacy = #"{"activeSessions":[],"blockApplied":false,"helper":"reachable","#
        + #""holds":[],"latchedCutouts":[],"shouldBlock":false}"#
    let decoded = try WireCodec.decodePayload(StatusReport.self, from: Data(legacy.utf8))
    #expect(decoded.alerts == nil)
    #expect(decoded == StatusReport(
        shouldBlock: false,
        blockApplied: false,
        helper: .reachable,
        activeSessions: [],
        holds: [],
        latchedCutouts: [],
        pausedUntil: nil
    ))
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

@Test func newReportWithAlertsDecodesUnderTheOldShape() throws {
    let report = StatusReport(
        shouldBlock: false,
        blockApplied: false,
        helper: .reachable,
        activeSessions: [],
        holds: [],
        latchedCutouts: [],
        pausedUntil: nil,
        alerts: [SleepAlert(id: 1, atEpoch: 1_767_000_000, payload: .released(sessions: 1, holds: 0))]
    )
    let encoded = try WireCodec.encodePayload(report)
    let legacy = try WireCodec.decodePayload(LegacyStatusReport.self, from: encoded)
    #expect(legacy == LegacyStatusReport(
        shouldBlock: false,
        blockApplied: false,
        helper: .reachable,
        activeSessions: [],
        holds: [],
        latchedCutouts: [],
        pausedUntil: nil
    ))
}

@Test func statusReportToleratesUnknownCutoutKind() throws {
    let json = #"{"activeSessions":[],"blockApplied":false,"helper":"reachable","#
        + #""holds":[],"latchedCutouts":["battery","teleport"],"shouldBlock":false}"#
    let decoded = try WireCodec.decodePayload(StatusReport.self, from: Data(json.utf8))
    #expect(decoded.latchedCutouts == [.battery, .unknown])
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
    let frame = try WireCodec.encodeFrame(WireResponse.status(report))
    let decoded = try #require(try WireCodec.decodeFrame(WireResponse.self, from: frame))
    #expect(decoded.value == .status(report))
}
