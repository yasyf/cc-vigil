import CCVigilShared
import Testing

private let activeOps: [WireRequest] = [
    .nudge(NudgePayload(sessionId: "s", hookEvent: "PreToolUse")),
    .hold(key: "k", reason: "r", ttlSeconds: 60, pid: nil),
    .release(key: "k"),
    .pause(seconds: 30),
]

private let passiveOps: [WireRequest] = [.status, .ping]

@Test func clearLatchesTheDaemonIntoTeardown() {
    var latch = ClearLatch()
    #expect(latch.isClearing == false)
    latch.fold(.clear)
    #expect(latch.isClearing)
}

@Test(arguments: activeOps)
func activeTrafficUnsticksAStrayClear(op: WireRequest) {
    var latch = ClearLatch()
    latch.fold(.clear)
    latch.fold(op)
    #expect(latch.isClearing == false)
}

@Test(arguments: passiveOps)
func passiveProbesLeaveTheTeardownLatchSet(op: WireRequest) {
    var latch = ClearLatch()
    latch.fold(.clear)
    latch.fold(op)
    #expect(latch.isClearing)
}
