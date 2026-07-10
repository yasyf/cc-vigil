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
    backgroundWork: [String: BackgroundWorkReport] = [:],
    sessionPids: [String: TrackedPid] = [:],
    processStart: (Int32) -> Int64? = { _ in nil },
    processesAlive: Bool = true,
    config: VigilConfig = .default
) -> BlockDecision {
    OracleState(
        sessions: sessions,
        humanWaitHints: hints,
        backgroundWork: backgroundWork,
        sessionPids: sessionPids,
        claudeProcessesAlive: processesAlive
    )
    .decision(config: config, clock: clock, processStart: processStart)
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

private func background(_ id: String = "b1") -> PendingItem {
    PendingItem(toolUseID: id, name: "Bash", kind: .background)
}

/// A live run_in_background Bash keeps the session active even after Claude Code
/// fires its idle Notification: the hint is newer than the frozen transcript
/// epoch, but machine-driven work outranks it. Past the activity window so the
/// hold rests on `.waiting` alone, not lingering recent activity (issue #7).
@Test func oracleLiveBackgroundJobOutranksHumanWaitHint() {
    let decision = decide(
        [probe(isWaiting: true, lastEventEpoch: now - 1000, pending: [background()])],
        hints: ["/t/session.jsonl": now]
    )
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: "/t/session.jsonl", reasons: [.waiting])],
        discounts: []
    ))
}

@Test func oracleLivePendingWorkflowOutranksHumanWaitHint() {
    let decision = decide(
        [probe(isWaiting: true, lastEventEpoch: now - 1000, pending: [asyncPending(.pendingAsyncWorkflow)])],
        hints: ["/t/session.jsonl": now]
    )
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: "/t/session.jsonl", reasons: [.waiting])],
        discounts: []
    ))
}

/// A Monitor (or ScheduleWakeup/SendMessage/TeamCreate) is a machine-driven wait
/// that never advances the transcript: a session parked on a Monitor watching a
/// background job is the issue-#7 scenario via `.waitingTool`, so the hint must
/// not discount it either.
@Test func oracleLiveWaitingToolOutranksHumanWaitHint() {
    let pending = [PendingItem(toolUseID: "m1", name: "Monitor", kind: .waitingTool)]
    let decision = decide(
        [probe(isWaiting: true, lastEventEpoch: now - 1000, pending: pending)],
        hints: ["/t/session.jsonl": now]
    )
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: "/t/session.jsonl", reasons: [.waiting])],
        discounts: []
    ))
}

/// A parked prompt carries no machine-driven pending work, so the idle hint still
/// lets the Mac sleep.
@Test func oracleParkedSessionStillDiscountsOnHumanWaitHint() {
    let decision = decide(
        [probe(lastEventEpoch: now - 50)],
        hints: ["/t/session.jsonl": now]
    )
    #expect(decision.shouldBlock == false)
    #expect(decision.activeSessions.isEmpty)
    #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .humanWaitHint)])
}

/// The gate demands the machine job be live: once it ages out past the max-age
/// backstop the stale-activity discount fires despite the hint, so a leaked
/// background job never pins sleep open forever.
@Test func oracleStaleBackgroundJobDiscountsDespiteHumanWaitHint() {
    let decision = decide(
        [probe(isWaiting: true, lastEventEpoch: now - 90000, pending: [background()])],
        hints: ["/t/session.jsonl": now]
    )
    #expect(decision.shouldBlock == false)
    #expect(decision.activeSessions.isEmpty)
    #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .staleActivityMaxAge)])
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

@Test(arguments: [
    (Int64(43200), true),
    (Int64(43201), false),
])
func oracleMidToolMaxAgeBackstopBoundary(ageSeconds: Int64, expectActive: Bool) {
    let decision = decide([probe(midTool: true, lastEventEpoch: now - ageSeconds)])
    #expect(decision.shouldBlock == expectActive)
    if expectActive {
        #expect(decision.activeSessions == [ActiveSession(path: "/t/session.jsonl", reasons: [.midTool])])
        #expect(decision.discounts.isEmpty)
    } else {
        #expect(decision.activeSessions.isEmpty)
        #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .staleActivityMaxAge)])
    }
}

@Test(arguments: [
    (Int64(43200), true),
    (Int64(43201), false),
])
func oracleWaitingMaxAgeBackstopBoundary(ageSeconds: Int64, expectActive: Bool) {
    let pending = [PendingItem(toolUseID: "m1", name: "Monitor", kind: .waitingTool)]
    let decision = decide([probe(isWaiting: true, lastEventEpoch: now - ageSeconds, pending: pending)])
    #expect(decision.shouldBlock == expectActive)
    if expectActive {
        #expect(decision.activeSessions == [ActiveSession(path: "/t/session.jsonl", reasons: [.waiting])])
        #expect(decision.discounts.isEmpty)
    } else {
        #expect(decision.activeSessions.isEmpty)
        #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .staleActivityMaxAge)])
    }
}

@Test func oracleBackstopDiscountsStaleMixedPendingWaiting() {
    let pending = [asyncPending(), PendingItem(toolUseID: "m1", name: "Monitor", kind: .waitingTool)]
    let decision = decide([probe(isWaiting: true, lastEventEpoch: now - 90000, pending: pending)])
    #expect(decision.shouldBlock == false)
    #expect(decision.activeSessions.isEmpty)
    #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .staleActivityMaxAge)])
}

@Test func oracleBackstopDiscountsStaleEmptyPendingWaiting() {
    let decision = decide([probe(isWaiting: true, lastEventEpoch: now - 90000)])
    #expect(decision.shouldBlock == false)
    #expect(decision.activeSessions.isEmpty)
    #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .staleActivityMaxAge)])
}

@Test func oracleBackstopDiscountsStaleMidToolSession() {
    let decision = decide([probe(
        isWaiting: true,
        midTool: true,
        lastEventEpoch: now - 90000,
        pending: [asyncPending()]
    )])
    #expect(decision.shouldBlock == false)
    #expect(decision.activeSessions.isEmpty)
    #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .staleActivityMaxAge)])
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

private enum PidMapping {
    case mappedLive, mappedDead, unmapped
}

private func liveness(
    _ mapping: PidMapping
) -> (sessionPids: [String: TrackedPid], processStart: (Int32) -> Int64?) {
    (
        sessionPids: mapping == .unmapped
            ? [:]
            : ["/t/session.jsonl": TrackedPid(pid: 77, capturedAtEpoch: now - 1000)],
        processStart: { _ in mapping == .mappedDead ? nil : now - 2000 }
    )
}

/// The full per-session-liveness matrix: {mapped-live, mapped-dead, unmapped}
/// × {fresh, stale (past the 12h cliff)} × {midTool, waitingTool pending}.
/// Mapped + dead discounts outright — a dead process writes nothing, so a
/// recent mtime cannot vouch for it and `.recentActivity` is suppressed.
/// Mapped + live holds past the cliff. Unmapped keeps today's uniform cliff
/// bit for bit — the unmapped rows pass a live-shaped `processStart` to prove
/// the map's absence, not the closure, drives the verdict. Self-heal note: a
/// --resume'd session briefly maps to its dead old pid until the next nudge
/// remaps it (latest-wins) and reads as the mapped-dead rows for that window,
/// bounded by one nudge interval; the global claudeProcessesAlive gate keeps
/// the machine awake while any claude process lives.
@Test(arguments: [
    (PidMapping.mappedLive, false, true, [ActivityReason.recentActivity, .midTool], DiscountReason?.none),
    (.mappedLive, false, false, [.recentActivity, .waiting], nil),
    (.mappedLive, true, true, [.midTool], nil),
    (.mappedLive, true, false, [.waiting], nil),
    (.mappedDead, false, true, [], .sessionProcessDead),
    (.mappedDead, false, false, [], .sessionProcessDead),
    (.mappedDead, true, true, [], .sessionProcessDead),
    (.mappedDead, true, false, [], .sessionProcessDead),
    (.unmapped, false, true, [.recentActivity, .midTool], nil),
    (.unmapped, false, false, [.recentActivity, .waiting], nil),
    (.unmapped, true, true, [], .staleActivityMaxAge),
    (.unmapped, true, false, [], .staleActivityMaxAge),
])
private func oraclePerSessionLivenessMatrix(
    mapping: PidMapping,
    stale: Bool,
    midTool: Bool,
    expectedReasons: [ActivityReason],
    expectedDiscount: DiscountReason?
) {
    let epoch = now - (stale ? 90000 : 10)
    let session = midTool
        ? probe(midTool: true, lastEventEpoch: epoch)
        : probe(
            isWaiting: true,
            lastEventEpoch: epoch,
            pending: [PendingItem(toolUseID: "m1", name: "Monitor", kind: .waitingTool)]
        )
    let (sessionPids, processStart) = liveness(mapping)
    let decision = decide([session], sessionPids: sessionPids, processStart: processStart)
    #expect(decision == BlockDecision(
        shouldBlock: !expectedReasons.isEmpty,
        activeSessions: expectedReasons.isEmpty
            ? []
            : [ActiveSession(path: "/t/session.jsonl", reasons: expectedReasons)],
        discounts: expectedDiscount.map { [SessionDiscount(path: "/t/session.jsonl", reason: $0)] } ?? []
    ))
}

/// The pid-reuse defense at the capture boundary, floored to whole seconds on
/// both sides: a start strictly after capture is a recycled pid (dead), the
/// capture instant itself is ambiguous and resolves live — flooring can only
/// turn a borderline reuse into live, the safe direction for a sleep
/// inhibitor. A stale midTool probe makes the verdict visible: live holds
/// past the cliff, dead discounts with `.sessionProcessDead`.
@Test(arguments: [
    (Int64?.none, false),
    (Int64?(now - 999), false),
    (Int64?(now - 1000), true),
    (Int64?(now - 2000), true),
])
func oracleSessionPidReuseBoundary(startedEpoch: Int64?, expectLive: Bool) {
    let decision = decide(
        [probe(midTool: true, lastEventEpoch: now - 90000)],
        sessionPids: ["/t/session.jsonl": TrackedPid(pid: 77, capturedAtEpoch: now - 1000)],
        processStart: { pid in
            #expect(pid == 77)
            return startedEpoch
        }
    )
    if expectLive {
        #expect(decision.activeSessions == [ActiveSession(path: "/t/session.jsonl", reasons: [.midTool])])
        #expect(decision.discounts.isEmpty)
    } else {
        #expect(decision.activeSessions.isEmpty)
        #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .sessionProcessDead)])
    }
}

@Test func oraclePidForOtherSessionLeavesThisOneUnmapped() {
    let decision = decide(
        [probe(midTool: true, lastEventEpoch: now - 90000)],
        sessionPids: ["/t/other.jsonl": TrackedPid(pid: 77, capturedAtEpoch: now - 1000)],
        processStart: { _ in nil }
    )
    #expect(decision.discounts == [SessionDiscount(path: "/t/session.jsonl", reason: .staleActivityMaxAge)])
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
