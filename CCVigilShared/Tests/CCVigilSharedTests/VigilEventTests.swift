import CCVigilShared
import Foundation
import Testing

private let at = Date(timeIntervalSince1970: 1_767_323_047)

private func json(_ record: EventRecord) throws -> String {
    let payload = try WireCodec.encodePayload(record)
    return try #require(String(bytes: payload, encoding: .utf8))
}

@Test func blockEdgeCarriesTheOracleSnapshot() throws {
    let decision = BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: "/t/a.jsonl", reasons: [.midTool, .waiting])],
        discounts: [SessionDiscount(path: "/t/b.jsonl", reason: .pendingAsyncMaxAge)]
    )
    let record = EventRecord(at: at, event: .blockEdge(blocked: true, applied: true, decision: decision, holds: []))
    #expect(try json(record) == "{\"applied\":true,\"at\":1767323047,\"blocked\":true,"
        + "\"decision\":{\"activeSessions\":[{\"path\":\"/t/a.jsonl\",\"reasons\":[\"mid-tool\",\"waiting\"]}],"
        + "\"discounts\":[{\"path\":\"/t/b.jsonl\",\"reason\":\"pending-async-max-age\"}],\"shouldBlock\":true},"
        + "\"event\":\"block-edge\",\"holds\":[]}")
}

@Test func blockEdgeEncodesSessionProcessDeadDiscountAdditively() throws {
    let decision = BlockDecision(
        shouldBlock: false,
        activeSessions: [],
        discounts: [SessionDiscount(path: "/t/dead.jsonl", reason: .sessionProcessDead)]
    )
    let record = EventRecord(at: at, event: .blockEdge(blocked: false, applied: false, decision: decision, holds: []))
    #expect(try json(record) == "{\"applied\":false,\"at\":1767323047,\"blocked\":false,"
        + "\"decision\":{\"activeSessions\":[],"
        + "\"discounts\":[{\"path\":\"/t/dead.jsonl\",\"reason\":\"session-process-dead\"}],\"shouldBlock\":false},"
        + "\"event\":\"block-edge\",\"holds\":[]}")
    #expect(try WireCodec.decodePayload(EventRecord.self, from: WireCodec.encodePayload(record)) == record)
}

@Test func holdDrivenBlockEdgeSelfDescribesWithItsActiveHolds() throws {
    let decision = BlockDecision(shouldBlock: false, activeSessions: [], discounts: [])
    let hold = Hold(key: "ci", reason: "cargo build", ttlSeconds: 600, createdAt: at, pid: 4242)
    let record = EventRecord(at: at, event: .blockEdge(blocked: true, applied: true, decision: decision, holds: [hold]))
    #expect(try json(record) == "{\"applied\":true,\"at\":1767323047,\"blocked\":true,"
        + "\"decision\":{\"activeSessions\":[],\"discounts\":[],\"shouldBlock\":false},"
        + "\"event\":\"block-edge\",\"holds\":[{\"createdAt\":1767323047,\"key\":\"ci\","
        + "\"pid\":4242,\"reason\":\"cargo build\",\"ttlSeconds\":600}]}")
}

@Test func preHoldsBlockEdgeDecodesWithNoHolds() throws {
    let line = "{\"applied\":true,\"at\":1767323047,\"blocked\":true,"
        + "\"decision\":{\"activeSessions\":[{\"path\":\"/t/a.jsonl\",\"reasons\":[\"mid-tool\"]}],"
        + "\"discounts\":[],\"shouldBlock\":true},\"event\":\"block-edge\"}"
    let decoded = try WireCodec.decodePayload(EventRecord.self, from: Data(line.utf8))
    let decision = BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: "/t/a.jsonl", reasons: [.midTool])],
        discounts: []
    )
    #expect(decoded == EventRecord(at: at, event: .blockEdge(blocked: true, applied: true, decision: decision, holds: [])))
}

@Test(arguments: [
    (EventRecord(at: at, event: .daemonStopped), "{\"at\":1767323047,\"event\":\"daemon-stopped\"}"),
    (
        EventRecord(at: at, event: .daemonStarted(version: "0.1.0", dryRun: true)),
        "{\"at\":1767323047,\"dryRun\":true,\"event\":\"daemon-started\",\"version\":\"0.1.0\"}"
    ),
    (
        EventRecord(at: at, event: .cutoutLatched(.battery)),
        "{\"at\":1767323047,\"event\":\"cutout-latched\",\"kind\":\"battery\"}"
    ),
    (
        EventRecord(at: at, event: .cutoutCleared(.thermal)),
        "{\"at\":1767323047,\"event\":\"cutout-cleared\",\"kind\":\"thermal\"}"
    ),
    (
        EventRecord(at: at, event: .lidChanged(closed: true)),
        "{\"at\":1767323047,\"closed\":true,\"event\":\"lid\"}"
    ),
    (
        EventRecord(at: at, event: .holdReleased(key: "ci")),
        "{\"at\":1767323047,\"event\":\"hold-released\",\"key\":\"ci\"}"
    ),
    (
        EventRecord(at: at, event: .holdsExpired(keys: ["a", "b"])),
        "{\"at\":1767323047,\"event\":\"holds-expired\",\"keys\":[\"a\",\"b\"]}"
    ),
    (
        EventRecord(at: at, event: .probeFailed(path: "/t/bad.jsonl", message: "parse error")),
        "{\"at\":1767323047,\"event\":\"probe-failed\",\"message\":\"parse error\",\"path\":\"/t/bad.jsonl\"}"
    ),
    (
        EventRecord(at: at, event: .paused(until: Date(timeIntervalSince1970: 1_767_323_100))),
        "{\"at\":1767323047,\"event\":\"paused\",\"until\":1767323100}"
    ),
    (EventRecord(at: at, event: .resumed), "{\"at\":1767323047,\"event\":\"resumed\"}"),
    (EventRecord(at: at, event: .wake), "{\"at\":1767323047,\"event\":\"wake\"}"),
])
func encodesExactJSON(record: EventRecord, expected: String) throws {
    #expect(try json(record) == expected)
}

@Test func holdAddedEncodesTheHold() throws {
    let hold = Hold(key: "ci", reason: "long build", ttlSeconds: 600, createdAt: at, pid: 42)
    let record = EventRecord(at: at, event: .holdAdded(hold))
    #expect(try json(record) == "{\"at\":1767323047,\"event\":\"hold-added\","
        + "\"hold\":{\"createdAt\":1767323047,\"key\":\"ci\",\"pid\":42,"
        + "\"reason\":\"long build\",\"ttlSeconds\":600}}")
}

@Test(arguments: [
    EventRecord(at: at, event: .daemonStarted(version: "1.2.3", dryRun: false)),
    EventRecord(
        at: at,
        event: .blockEdge(
            blocked: false,
            applied: false,
            decision: BlockDecision(shouldBlock: false, activeSessions: [], discounts: []),
            holds: [Hold(key: "k", reason: "r", ttlSeconds: 60, createdAt: at, pid: nil)]
        )
    ),
    EventRecord(at: at, event: .holdAdded(Hold(key: "k", reason: "r", ttlSeconds: 60, createdAt: at, pid: nil))),
    EventRecord(at: at, event: .paused(until: at)),
    EventRecord(at: at, event: .wake),
])
func roundTrips(record: EventRecord) throws {
    let encoded = try WireCodec.encodePayload(record)
    #expect(try WireCodec.decodePayload(EventRecord.self, from: encoded) == record)
}

@Test func persistedStateEncodesExactJSON() throws {
    let state = PersistedState(
        holds: [Hold(key: "ci", reason: "build", ttlSeconds: 60, createdAt: at, pid: nil)],
        pausedUntil: Date(timeIntervalSince1970: 1_767_323_100),
        registeredRoots: ["/relocated/.claude/projects"]
    )
    let encoded = try #require(String(bytes: WireCodec.encodePayload(state), encoding: .utf8))
    #expect(encoded == "{\"alertedCutouts\":[],\"holds\":[{\"createdAt\":1767323047,\"key\":\"ci\","
        + "\"reason\":\"build\",\"ttlSeconds\":60}],\"nextAlertId\":1,\"pausedUntil\":1767323100,"
        + "\"recentAlerts\":[],\"registeredRoots\":[\"/relocated/.claude/projects\"]}")
    #expect(try WireCodec.decodePayload(PersistedState.self, from: Data(encoded.utf8)) == state)
}

@Test func persistedStateRoundTripsAlertFields() throws {
    let state = PersistedState(
        holds: [],
        pausedUntil: nil,
        nextAlertId: 7,
        recentAlerts: [
            SleepAlert(id: 5, atEpoch: 1_767_323_047, payload: .released(sessions: 2, holds: 1)),
            SleepAlert(id: 6, atEpoch: 1_767_323_100, payload: .cutoutLatched(kinds: [.battery, .thermal])),
        ]
    )
    let encoded = try WireCodec.encodePayload(state)
    #expect(try WireCodec.decodePayload(PersistedState.self, from: encoded) == state)
}

@Test func persistedStateRoundTripsAlertedCutouts() throws {
    let state = PersistedState(
        holds: [],
        pausedUntil: nil,
        alertedCutouts: [.battery, .thermal]
    )
    let encoded = try WireCodec.encodePayload(state)
    #expect(try WireCodec.decodePayload(PersistedState.self, from: encoded) == state)
}
