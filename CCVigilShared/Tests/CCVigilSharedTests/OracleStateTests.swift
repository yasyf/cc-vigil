import CCVigilShared
import Foundation
import Testing

private let now: Int64 = 1_800_000_000
private let clock = FixedClock(epoch: now)

private func probe(
    path: String = "/t/session.jsonl",
    isWaiting: Bool = false,
    midTool: Bool = false,
    lastEventEpoch: Int64? = nil,
    pending: [PendingItem] = []
) -> SessionProbe {
    SessionProbe(
        sessionPath: path,
        isWaiting: isWaiting,
        midTool: midTool,
        lastEventEpoch: lastEventEpoch,
        pending: pending
    )
}

private func decide(
    _ sessions: [SessionProbe],
    hints: [String: Int64] = [:],
    processesAlive: Bool = true,
    config: VigilConfig = .default
) -> BlockDecision {
    OracleState(sessions: sessions, humanWaitHints: hints, claudeProcessesAlive: processesAlive)
        .decision(config: config, clock: clock)
}

private func asyncPending(_ kind: PendingKind = .pendingAsyncWorkflow) -> PendingItem {
    PendingItem(toolUseID: "wf1", name: "Workflow", kind: kind)
}

@Test func oracleProcessGateClosedIdlesEverything() {
    let decision = decide(
        [probe(isWaiting: true, midTool: true, lastEventEpoch: now)],
        processesAlive: false
    )
    #expect(decision == BlockDecision(shouldBlock: false, activeSessions: [], discounts: []))
}

@Test func oracleNoSessionsMeansNoBlock() {
    #expect(decide([]) == BlockDecision(shouldBlock: false, activeSessions: [], discounts: []))
}

@Test(arguments: [
    (0, true),
    (300, true),
    (301, false),
])
func oracleActivityWindowBoundary(ageSeconds: Int64, expectActive: Bool) {
    let decision = decide([probe(lastEventEpoch: now - ageSeconds)])
    #expect(decision.shouldBlock == expectActive)
    if expectActive {
        #expect(decision.activeSessions == [
            ActiveSession(path: "/t/session.jsonl", reasons: [.recentActivity]),
        ])
    } else {
        #expect(decision.activeSessions.isEmpty)
    }
    #expect(decision.discounts.isEmpty)
}

@Test func oracleRespectsConfiguredActivityWindow() throws {
    let config = try VigilConfig(activityWindowSeconds: 60)
    let decision = decide([probe(lastEventEpoch: now - 61)], config: config)
    #expect(decision.shouldBlock == false)
}

@Test func oracleMidToolKeepsStaleSessionActive() {
    let decision = decide([probe(midTool: true, lastEventEpoch: now - 4000)])
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: "/t/session.jsonl", reasons: [.midTool])],
        discounts: []
    ))
}

@Test func oracleWaitingToolKeepsStaleSessionActive() {
    let pending = [PendingItem(toolUseID: "m1", name: "Monitor", kind: .waitingTool)]
    let decision = decide([probe(isWaiting: true, lastEventEpoch: now - 4000, pending: pending)])
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: "/t/session.jsonl", reasons: [.waiting])],
        discounts: []
    ))
}

@Test func oracleReasonsComposeInStableOrder() {
    let pending = [PendingItem(toolUseID: "m1", name: "Monitor", kind: .waitingTool)]
    let decision = decide([probe(isWaiting: true, midTool: true, lastEventEpoch: now - 10, pending: pending)])
    #expect(decision.activeSessions == [
        ActiveSession(path: "/t/session.jsonl", reasons: [.recentActivity, .midTool, .waiting]),
    ])
}

@Test(arguments: [
    (Int64?(now - 100), now - 50, false),
    (Int64?(now - 100), now - 100, true),
    (Int64?(now - 100), now - 200, true),
    (Int64?.none, now - 50, false),
])
func oracleHumanWaitHintDiscount(lastEventEpoch: Int64?, hintEpoch: Int64, expectActive: Bool) {
    let decision = decide(
        [probe(isWaiting: true, midTool: true, lastEventEpoch: lastEventEpoch)],
        hints: ["/t/session.jsonl": hintEpoch]
    )
    #expect(decision.shouldBlock == expectActive)
    if expectActive {
        #expect(decision.discounts.isEmpty)
    } else {
        #expect(decision.activeSessions.isEmpty)
        #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .humanWaitHint)])
    }
}

@Test func oracleHintForOtherSessionDoesNotDiscount() {
    let decision = decide(
        [probe(lastEventEpoch: now - 10)],
        hints: ["/t/other.jsonl": now]
    )
    #expect(decision.shouldBlock == true)
    #expect(decision.discounts.isEmpty)
}

@Test(arguments: [
    (Int64(43200), true),
    (Int64(43201), false),
])
func oraclePendingAsyncBackstopBoundary(ageSeconds: Int64, expectActive: Bool) {
    let decision = decide([probe(
        isWaiting: true,
        lastEventEpoch: now - ageSeconds,
        pending: [asyncPending(.pendingAsyncWorkflow), asyncPending(.pendingAsyncTask)]
    )])
    #expect(decision.shouldBlock == expectActive)
    if expectActive {
        #expect(decision.activeSessions == [
            ActiveSession(path: "/t/session.jsonl", reasons: [.waiting]),
        ])
        #expect(decision.discounts.isEmpty)
    } else {
        #expect(decision.activeSessions.isEmpty)
        #expect(decision.discounts == [
            SessionDiscount(path: "/t/session.jsonl", reason: .pendingAsyncMaxAge),
        ])
    }
}

@Test func oracleBackstopRespectsConfiguredMaxAge() throws {
    let config = try VigilConfig(pendingAsyncMaxAgeSeconds: 400)
    let decision = decide(
        [probe(isWaiting: true, lastEventEpoch: now - 401, pending: [asyncPending()])],
        config: config
    )
    #expect(decision.shouldBlock == false)
    #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .pendingAsyncMaxAge)])
}

@Test func oracleBackstopTreatsMissingEpochAsStale() {
    let decision = decide([probe(isWaiting: true, lastEventEpoch: nil, pending: [asyncPending()])])
    #expect(decision.shouldBlock == false)
    #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .pendingAsyncMaxAge)])
}

@Test func oracleBackstopSparesMixedPending() {
    let pending = [asyncPending(), PendingItem(toolUseID: "m1", name: "Monitor", kind: .waitingTool)]
    let decision = decide([probe(isWaiting: true, lastEventEpoch: now - 90000, pending: pending)])
    #expect(decision.shouldBlock == true)
    #expect(decision.activeSessions == [ActiveSession(path: "/t/session.jsonl", reasons: [.waiting])])
    #expect(decision.discounts.isEmpty)
}

@Test func oracleBackstopSparesEmptyPending() {
    let decision = decide([probe(isWaiting: true, lastEventEpoch: now - 90000)])
    #expect(decision.shouldBlock == true)
    #expect(decision.activeSessions == [ActiveSession(path: "/t/session.jsonl", reasons: [.waiting])])
}

@Test func oracleBackstopRecordsDiscountEvenWhenMidToolKeepsSessionActive() {
    let decision = decide([probe(
        isWaiting: true,
        midTool: true,
        lastEventEpoch: now - 90000,
        pending: [asyncPending()]
    )])
    #expect(decision.shouldBlock == true)
    #expect(decision.activeSessions == [ActiveSession(path: "/t/session.jsonl", reasons: [.midTool])])
    #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .pendingAsyncMaxAge)])
}

@Test func oracleComposesMultipleSessionsPreservingOrder() {
    let decision = decide([
        probe(path: "/t/idle.jsonl", lastEventEpoch: now - 4000),
        probe(path: "/t/recent.jsonl", lastEventEpoch: now - 10),
        probe(path: "/t/tooling.jsonl", midTool: true, lastEventEpoch: now - 4000),
    ])
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [
            ActiveSession(path: "/t/recent.jsonl", reasons: [.recentActivity]),
            ActiveSession(path: "/t/tooling.jsonl", reasons: [.midTool]),
        ],
        discounts: []
    ))
}

@Test(arguments: [
    (PendingKind.waitingTool, "waiting_tool", false),
    (PendingKind.background, "background", false),
    (PendingKind.subagentlessTask, "subagentless_task", false),
    (PendingKind.pendingAsyncTask, "pending_async_task", true),
    (PendingKind.pendingAsyncWorkflow, "pending_async_workflow", true),
    (PendingKind.midTool, "mid_tool", false),
])
func pendingKindWireValues(kind: PendingKind, rawValue: String, isPendingAsync: Bool) {
    #expect(kind.rawValue == rawValue)
    #expect(kind.isPendingAsync == isPendingAsync)
}
