import CCVigilDaemonKit
import CCVigilShared
import Foundation
import Testing

@Test func composesFixturesIntoABlockingDecision() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let recent = try transcripts.install(fixture: "active-recent", as: "recent.jsonl")
    let midTool = try transcripts.install(fixture: "mid-tool", as: "midtool.jsonl")
    let waiting = try transcripts.install(fixture: "waiting-workflow", as: "waiting.jsonl")

    let oracle = TranscriptOracle(roots: [transcripts.root])
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 60)
    let collection = oracle.collect(config: .default, clock: clock)
    #expect(collection.newFailures == [])
    #expect(collection.probes.count == 3)

    let decision = OracleState(
        sessions: collection.probes,
        humanWaitHints: [:],
        backgroundWork: [:],
        claudeProcessesAlive: true
    ).decision(config: .default, clock: clock)
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [
            ActiveSession(path: midTool.path, reasons: [.recentActivity, .midTool]),
            ActiveSession(path: recent.path, reasons: [.recentActivity]),
            ActiveSession(path: waiting.path, reasons: [.recentActivity, .waiting]),
        ],
        discounts: []
    ))
}

@Test func staleTranscriptsOutsideActivityWindowGoIdle() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    try transcripts.install(fixture: "active-recent", as: "recent.jsonl")

    let oracle = TranscriptOracle(roots: [transcripts.root])
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 301)
    let collection = oracle.collect(config: .default, clock: clock)
    let decision = OracleState(
        sessions: collection.probes,
        humanWaitHints: [:],
        backgroundWork: [:],
        claudeProcessesAlive: true
    ).decision(config: .default, clock: clock)
    #expect(decision == BlockDecision(shouldBlock: false, activeSessions: [], discounts: []))
}

@Test func stalePendingWorkflowHitsTheMaxAgeBackstop() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let waiting = try transcripts.install(fixture: "waiting-workflow", as: "waiting.jsonl")

    let oracle = TranscriptOracle(roots: [transcripts.root])
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 45000)
    let collection = oracle.collect(config: .default, clock: clock)
    #expect(collection.probes.count == 1)
    let decision = OracleState(
        sessions: collection.probes,
        humanWaitHints: [:],
        backgroundWork: [:],
        claudeProcessesAlive: true
    ).decision(config: .default, clock: clock)
    #expect(decision == BlockDecision(
        shouldBlock: false,
        activeSessions: [],
        discounts: [SessionDiscount(path: waiting.path, reason: .pendingAsyncMaxAge)]
    ))
}

@Test func humanWaitHintDiscountsAFreshSession() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let recent = try transcripts.install(fixture: "active-recent", as: "abc-123.jsonl")

    let oracle = TranscriptOracle(roots: [transcripts.root])
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 60)
    let collection = oracle.collect(config: .default, clock: clock)
    var tracker = HintTracker()
    tracker.apply(
        NudgePayload(sessionId: "abc-123", hookEvent: "Notification", notificationKind: "idle_prompt"),
        now: Date(timeIntervalSince1970: TimeInterval(fixtureLastEventEpoch + 30))
    )
    let decision = OracleState(
        sessions: collection.probes,
        humanWaitHints: tracker.hints(forPaths: collection.probes.map(\.sessionPath)),
        backgroundWork: [:],
        claudeProcessesAlive: true
    ).decision(config: .default, clock: clock)
    #expect(decision == BlockDecision(
        shouldBlock: false,
        activeSessions: [],
        discounts: [SessionDiscount(path: recent.path, reason: .humanWaitHint)]
    ))
}

@Test func transcriptsOutsideTheMtimeWindowAreNotProbed() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let window = Int64(TranscriptDiscoveryPolicy.windowSeconds(config: .default))
    try transcripts.install(
        fixture: "waiting-workflow",
        as: "ancient.jsonl",
        mtimeEpoch: fixtureLastEventEpoch - window - 100
    )

    let oracle = TranscriptOracle(roots: [transcripts.root])
    let collection = oracle.collect(config: .default, clock: FixedClock(epoch: fixtureLastEventEpoch))
    #expect(collection.probes == [])
    #expect(collection.newFailures == [])
}

@Test func cachesProbesByPathMtimeAndSize() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let path = try transcripts.install(fixture: "active-recent", as: "recent.jsonl")

    let oracle = TranscriptOracle(roots: [transcripts.root])
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 60)
    let first = oracle.collect(config: .default, clock: clock)
    let firstProbe = SessionProbe(
        sessionPath: path.path,
        isWaiting: false,
        midTool: false,
        lastEventEpoch: fixtureLastEventEpoch,
        pending: []
    )
    #expect(first.probes == [firstProbe])

    // Shift the last event's timestamp in place by +300s. The byte count and
    // mtime are unchanged, so the (path, mtime, size, fileID) key stays
    // identical, but a re-parse would move lastEventEpoch — the returned value
    // reveals whether the entry was keyed or re-parsed.
    let shiftedEpoch = fixtureLastEventEpoch + 300
    let original = try Data(contentsOf: path)
    var shifted = try String(contentsOf: path, encoding: .utf8)
    shifted = shifted.replacingOccurrences(
        of: "\"timestamp\":\"2026-01-02T03:04:07Z\"",
        with: "\"timestamp\":\"2026-01-02T03:09:07Z\""
    )
    try Data(shifted.utf8).write(to: path)
    #expect(try Data(contentsOf: path).count == original.count)
    try transcripts.setMtime(path, epoch: fixtureLastEventEpoch)

    // Same key: the cache must hand back the OLD probe, not the shifted content.
    let cached = oracle.collect(config: .default, clock: clock)
    #expect(cached.probes == [firstProbe])

    // A changed mtime invalidates the entry and forces a fresh probe that
    // reflects the shifted timestamp.
    try transcripts.setMtime(path, epoch: fixtureLastEventEpoch + 5)
    let fresh = oracle.collect(config: .default, clock: clock)
    #expect(fresh.probes == [SessionProbe(
        sessionPath: path.path,
        isWaiting: false,
        midTool: false,
        lastEventEpoch: shiftedEpoch,
        pending: []
    )])
    #expect(fresh.probes != first.probes)
}

@Test func cachedFailedProbeStillReassertsTheLastKnownGood() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let session = try transcripts.install(fixture: "mid-tool", as: "session.jsonl")

    // First pass parses cleanly: the mid-tool probe is cached as last-known-good.
    let oracle = TranscriptOracle(roots: [transcripts.root])
    let good = oracle.collect(config: .default, clock: FixedClock(epoch: fixtureLastEventEpoch + 60))
    let lastKnownGood = SessionProbe(
        sessionPath: session.path,
        isWaiting: false,
        midTool: true,
        lastEventEpoch: fixtureLastEventEpoch,
        pending: [PendingItem(toolUseID: "b1", name: "Bash", kind: .midTool)]
    )
    #expect(good.probes == [lastKnownGood])

    // A poison line lands; the transcript stops parsing. Its mtime stays put.
    let malformedLine = try String(contentsOf: fixtureURL("malformed"), encoding: .utf8)
    let poisoned = try String(contentsOf: session, encoding: .utf8) + "\n" + malformedLine
    try Data(poisoned.utf8).write(to: session)
    try transcripts.setMtime(session, epoch: fixtureLastEventEpoch)

    // 301s later: past the 5-min recency window but inside the 12h mid-tool cap.
    // The first failed collect logs loudly and reasserts the last-known-good.
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 301)
    let firstFailure = oracle.collect(config: .default, clock: clock)
    #expect(firstFailure.newFailures.count == 1)
    #expect(firstFailure.probes == [lastKnownGood])

    // The same (path, mtime, size, fileID) now serves the cached .failed outcome
    // from the cache-hit path — silent this time — and it must STILL reassert the
    // last-known-good rather than drop through to a bare recency probe.
    let cachedFailure = oracle.collect(config: .default, clock: clock)
    #expect(cachedFailure.newFailures == [])
    #expect(cachedFailure.probes == [lastKnownGood])

    // The reasserted mid-tool probe holds the session active past recency.
    let decision = OracleState(
        sessions: cachedFailure.probes,
        humanWaitHints: [:],
        backgroundWork: [:],
        claudeProcessesAlive: true
    ).decision(config: .default, clock: clock)
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: session.path, reasons: [.midTool])],
        discounts: []
    ))
}

@Test func probeFailuresAreLoudOnceAndFallBackToARecencyProbe() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let bad = try transcripts.install(fixture: "malformed", as: "bad.jsonl")
    try transcripts.install(fixture: "active-recent", as: "good.jsonl")

    let oracle = TranscriptOracle(roots: [transcripts.root])
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 60)
    let first = oracle.collect(config: .default, clock: clock)
    #expect(first.probes.count == 2)
    #expect(first.newFailures.count == 1)
    let failure = try #require(first.newFailures.first)
    #expect(failure.path == bad.path)
    #expect(!failure.message.isEmpty)

    // The failure is cached under the same keying: no repeat loud log.
    let second = oracle.collect(config: .default, clock: clock)
    #expect(second.probes == first.probes)
    #expect(second.newFailures == [])
}

@Test func freshFailedProbeContributesARecencyProbeSoTheSessionStaysActive() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let poisoned = try transcripts.install(fixture: "malformed", as: "poisoned.jsonl")

    let oracle = TranscriptOracle(roots: [transcripts.root])
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 60)
    let collection = oracle.collect(config: .default, clock: clock)
    #expect(collection.newFailures.count == 1)
    #expect(collection.probes == [SessionProbe(
        sessionPath: poisoned.path,
        isWaiting: false,
        midTool: false,
        lastEventEpoch: fixtureLastEventEpoch,
        pending: []
    )])

    let decision = OracleState(
        sessions: collection.probes,
        humanWaitHints: [:],
        backgroundWork: [:],
        claudeProcessesAlive: true
    ).decision(config: .default, clock: clock)
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: poisoned.path, reasons: [.recentActivity])],
        discounts: []
    ))
}

@Test func staleFailedProbeGoesIdle() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let poisoned = try transcripts.install(fixture: "malformed", as: "poisoned.jsonl")

    let oracle = TranscriptOracle(roots: [transcripts.root])
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 301)
    let collection = oracle.collect(config: .default, clock: clock)
    #expect(collection.probes == [SessionProbe(
        sessionPath: poisoned.path,
        isWaiting: false,
        midTool: false,
        lastEventEpoch: fixtureLastEventEpoch,
        pending: []
    )])

    let decision = OracleState(
        sessions: collection.probes,
        humanWaitHints: [:],
        backgroundWork: [:],
        claudeProcessesAlive: true
    ).decision(config: .default, clock: clock)
    #expect(decision == BlockDecision(shouldBlock: false, activeSessions: [], discounts: []))
}

@Test func failedProbeAfterAGoodMidToolReusesTheLastKnownGoodAndStaysActive() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let session = try transcripts.install(fixture: "mid-tool", as: "session.jsonl")

    // First pass parses cleanly: the mid-tool probe is cached as last-known-good.
    let oracle = TranscriptOracle(roots: [transcripts.root])
    let good = oracle.collect(config: .default, clock: FixedClock(epoch: fixtureLastEventEpoch + 60))
    #expect(good.newFailures == [])
    #expect(good.probes == [SessionProbe(
        sessionPath: session.path,
        isWaiting: false,
        midTool: true,
        lastEventEpoch: fixtureLastEventEpoch,
        pending: [PendingItem(toolUseID: "b1", name: "Bash", kind: .midTool)]
    )])

    // A poison line lands in the transcript, so it no longer parses. The session
    // wrote its tool_use then went quiet on a long build: its mtime stays put.
    let malformedLine = try String(contentsOf: fixtureURL("malformed"), encoding: .utf8)
    let poisoned = try String(contentsOf: session, encoding: .utf8) + "\n" + malformedLine
    try Data(poisoned.utf8).write(to: session)
    try transcripts.setMtime(session, epoch: fixtureLastEventEpoch)

    // 301s later: past the 5-min recency window but well inside the 12h mid-tool
    // cap. The last-known-good mid-tool probe must hold the session active.
    let clock = FixedClock(epoch: fixtureLastEventEpoch + 301)
    let collection = oracle.collect(config: .default, clock: clock)
    #expect(collection.newFailures.count == 1)
    #expect(collection.probes == [SessionProbe(
        sessionPath: session.path,
        isWaiting: false,
        midTool: true,
        lastEventEpoch: fixtureLastEventEpoch,
        pending: [PendingItem(toolUseID: "b1", name: "Bash", kind: .midTool)]
    )])

    let decision = OracleState(
        sessions: collection.probes,
        humanWaitHints: [:],
        backgroundWork: [:],
        claudeProcessesAlive: true
    ).decision(config: .default, clock: clock)
    #expect(decision == BlockDecision(
        shouldBlock: true,
        activeSessions: [ActiveSession(path: session.path, reasons: [.midTool])],
        discounts: []
    ))
}
