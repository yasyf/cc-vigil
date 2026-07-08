import CCVigilShared
import Testing

private final class FakeIdleAssertion: IdleAssertionControlling {
    var createResult = true
    private(set) var createCalls = 0
    private(set) var releaseCalls = 0

    func create() -> Bool {
        createCalls += 1
        return createResult
    }

    func release() {
        releaseCalls += 1
    }
}

private final class FakeClamshell: ClamshellControlling {
    var result = PmsetRunResult.exited(status: 0, stderr: "")
    private(set) var calls: [Bool] = []

    func setDisableSleep(_ disableSleep: Bool) -> PmsetRunResult {
        calls.append(disableSleep)
        return result
    }
}

@Test func blockerStartsUnknownAndNotBlocking() {
    let blocker = SleepBlocker(assertion: FakeIdleAssertion(), clamshell: FakeClamshell())
    #expect(blocker.state == SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: nil))
    #expect(blocker.isBlocking == false)
}

@Test func blockerAppliesAssertionAndPmsetOnBlock() {
    let assertion = FakeIdleAssertion()
    let clamshell = FakeClamshell()
    let blocker = SleepBlocker(assertion: assertion, clamshell: clamshell)
    let report = blocker.setBlocked(true)
    #expect(report == SleepBlockReport(
        state: SleepBlockState(desired: true, assertionHeld: true, pmsetDisableSleep: true),
        pmset: .exited(status: 0, stderr: "")
    ))
    #expect(report.state.isSettled == true)
    #expect(blocker.isBlocking == true)
    #expect(assertion.createCalls == 1)
    #expect(assertion.releaseCalls == 0)
    #expect(clamshell.calls == [true])
}

@Test func blockerReleasesAndClearsOnUnblock() {
    let assertion = FakeIdleAssertion()
    let clamshell = FakeClamshell()
    let blocker = SleepBlocker(assertion: assertion, clamshell: clamshell)
    _ = blocker.setBlocked(true)
    let report = blocker.setBlocked(false)
    #expect(report.state == SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: false))
    #expect(report.state.isSettled == true)
    #expect(blocker.isBlocking == false)
    #expect(assertion.releaseCalls == 1)
    #expect(clamshell.calls == [true, false])
}

@Test func blockerForceClearsEvenWhenNeverBlocked() {
    let assertion = FakeIdleAssertion()
    let clamshell = FakeClamshell()
    let blocker = SleepBlocker(assertion: assertion, clamshell: clamshell)
    let report = blocker.setBlocked(false)
    #expect(report.state == SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: false))
    #expect(assertion.releaseCalls == 1)
    #expect(clamshell.calls == [false])
}

@Test func blockerRerunsFullPairOnRepeatedBlock() {
    let assertion = FakeIdleAssertion()
    let clamshell = FakeClamshell()
    let blocker = SleepBlocker(assertion: assertion, clamshell: clamshell)
    _ = blocker.setBlocked(true)
    _ = blocker.setBlocked(true)
    #expect(assertion.createCalls == 2)
    #expect(clamshell.calls == [true, true])
    #expect(blocker.isBlocking == true)
}

@Test(arguments: [
    PmsetRunResult.exited(status: 1, stderr: "needs root"),
    PmsetRunResult.watchdogTimedOut(stderr: ""),
    PmsetRunResult.launchFailed(message: "ENOENT"),
])
func blockerPmsetFailureLeavesUnsettledUnknown(failure: PmsetRunResult) {
    let clamshell = FakeClamshell()
    clamshell.result = failure
    let blocker = SleepBlocker(assertion: FakeIdleAssertion(), clamshell: clamshell)
    let report = blocker.setBlocked(true)
    #expect(report.state == SleepBlockState(desired: true, assertionHeld: true, pmsetDisableSleep: nil))
    #expect(report.state.isSettled == false)
    #expect(report.pmset == failure)
    #expect(blocker.isBlocking == false)
}

@Test func blockerAssertionFailureLeavesUnsettled() {
    let assertion = FakeIdleAssertion()
    assertion.createResult = false
    let blocker = SleepBlocker(assertion: assertion, clamshell: FakeClamshell())
    let report = blocker.setBlocked(true)
    #expect(report.state == SleepBlockState(desired: true, assertionHeld: false, pmsetDisableSleep: true))
    #expect(report.state.isSettled == false)
    #expect(blocker.isBlocking == false)
}
