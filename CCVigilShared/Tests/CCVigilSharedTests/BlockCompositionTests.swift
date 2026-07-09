import CCVigilShared
import Testing

private func compose(
    shouldBlock: Bool = false,
    hasActiveHolds: Bool = false,
    paused: Bool = false,
    latchRejectsAcquire: Bool = false,
    shuttingDown: Bool = false
) -> BlockComposition {
    BlockComposition(
        shouldBlock: shouldBlock,
        hasActiveHolds: hasActiveHolds,
        paused: paused,
        latchRejectsAcquire: latchRejectsAcquire,
        shuttingDown: shuttingDown
    )
}

@Test func oracleDecisionAloneBlocks() {
    #expect(compose(shouldBlock: true).desired)
}

@Test func holdsSustainABlockWithZeroSessions() {
    #expect(compose(shouldBlock: false, hasActiveHolds: true).desired)
}

@Test func idleWithNoHoldsDoesNotBlock() {
    #expect(compose(shouldBlock: false, hasActiveHolds: false).desired == false)
}

@Test func pauseOverridesAnActiveBlock() {
    #expect(compose(shouldBlock: true, hasActiveHolds: true, paused: true).desired == false)
}

@Test func latchRejectsAnActiveBlock() {
    #expect(compose(shouldBlock: true, latchRejectsAcquire: true).desired == false)
}

@Test func shuttingDownForcesRelease() {
    #expect(compose(shouldBlock: true, hasActiveHolds: true, shuttingDown: true).desired == false)
}

@Test(arguments: [
    (true, false, false),
    (false, true, false),
    (false, false, true),
    (true, true, true),
])
func anyOverrideReleasesRegardlessOfDemand(paused: Bool, latch: Bool, shutting: Bool) {
    let composition = compose(
        shouldBlock: true,
        hasActiveHolds: true,
        paused: paused,
        latchRejectsAcquire: latch,
        shuttingDown: shutting
    )
    #expect(composition.desired == false)
}
