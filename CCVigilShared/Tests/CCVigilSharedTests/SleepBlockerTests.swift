import CCVigilShared
import Foundation
import Testing

private final class FakeIdleAssertion: IdleAssertionControlling {
    var createResult = true
    private(set) var creates: [IdleAssertionDescriptor] = []
    private(set) var releaseCalls = 0
    /// Net assertions held: a successful create re-arms the single live assertion
    /// (stays 1, never accumulates), a release drops it. Models the real helper's
    /// create-new-then-release-old re-arm so a leak would surface as liveCount > 1.
    private(set) var liveCount = 0

    func create(_ descriptor: IdleAssertionDescriptor) -> Bool {
        creates.append(descriptor)
        guard createResult else {
            return false
        }
        liveCount = 1
        return true
    }

    func release() {
        releaseCalls += 1
        liveCount = 0
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

private final class SequencedClamshell: ClamshellControlling {
    private var results: [PmsetRunResult]
    private(set) var calls: [Bool] = []

    init(_ results: [PmsetRunResult]) {
        precondition(!results.isEmpty)
        self.results = results
    }

    func setDisableSleep(_ disableSleep: Bool) -> PmsetRunResult {
        calls.append(disableSleep)
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}

private func helperExecutable(inAppAt appPath: String) -> URL {
    URL(fileURLWithPath: "\(appPath)/Contents/Library/LaunchDaemons/CCVigilHelper")
}

@Test func blockerStartsUnknownAndNotBlocking() {
    let blocker = SleepBlocker(assertion: FakeIdleAssertion(), clamshell: FakeClamshell(), descriptor: .test)
    #expect(blocker.state == SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: nil))
    #expect(blocker.isBlocking == false)
}

@Test func blockerAppliesAssertionAndPmsetOnBlock() {
    let assertion = FakeIdleAssertion()
    let clamshell = FakeClamshell()
    let blocker = SleepBlocker(assertion: assertion, clamshell: clamshell, descriptor: .test)
    let report = blocker.setBlocked(true)
    #expect(report == SleepBlockReport(
        state: SleepBlockState(desired: true, assertionHeld: true, pmsetDisableSleep: true),
        pmset: .exited(status: 0, stderr: "")
    ))
    #expect(report.state.isSettled == true)
    #expect(blocker.isBlocking == true)
    #expect(assertion.creates.count == 1)
    #expect(assertion.releaseCalls == 0)
    #expect(clamshell.calls == [true])
}

@Test func blockCarriesAttributedAssertionProperties() {
    let assertion = FakeIdleAssertion()
    let descriptor = IdleAssertionDescriptor.ccVigil(
        localizationBundlePath: IdleAssertionDescriptor.appBundlePath(
            forHelperExecutableAt: helperExecutable(inAppAt: "/Applications/CCVigil.app")
        )
    )
    let blocker = SleepBlocker(assertion: assertion, clamshell: FakeClamshell(), descriptor: descriptor)
    _ = blocker.setBlocked(true)
    #expect(assertion.creates == [descriptor])
    let recorded = assertion.creates[0]
    #expect(recorded.type == .preventUserIdleSystemSleep)
    #expect(recorded.name == "cc-vigil: agents active")
    #expect(recorded.reason == "Claude Code agents are working; cc-vigil is holding the system awake")
    #expect(recorded.details == "cc-vigil helper")
    #expect(recorded.localizationBundlePath == "/Applications/CCVigil.app")
    #expect(recorded.timeout == 900)
    #expect(recorded.timeoutAction == .release)
}

@Test(arguments: [
    "/Applications/CCVigil.app",
    "/Users/ada/Applications/CCVigil.app",
    "/Volumes/CCVigil/CCVigil.app",
])
func appBundlePathWalksUpToTheEnclosingAppBundle(appPath: String) {
    let derived = IdleAssertionDescriptor.appBundlePath(forHelperExecutableAt: helperExecutable(inAppAt: appPath))
    #expect(derived == appPath)
}

@Test func blockForwardsConfiguredDescriptor() {
    let assertion = FakeIdleAssertion()
    let descriptor = IdleAssertionDescriptor(
        type: .preventUserIdleSystemSleep,
        name: "custom",
        reason: "custom reason",
        details: "custom details",
        localizationBundlePath: "/custom/Bundle.app",
        timeout: 42,
        timeoutAction: .release
    )
    let blocker = SleepBlocker(assertion: assertion, clamshell: FakeClamshell(), descriptor: descriptor)
    _ = blocker.setBlocked(true)
    #expect(assertion.creates == [descriptor])
}

@Test func repeatedBlockReArmsAssertionWithoutLeaking() {
    let assertion = FakeIdleAssertion()
    let clamshell = FakeClamshell()
    let blocker = SleepBlocker(assertion: assertion, clamshell: clamshell, descriptor: .test)
    _ = blocker.setBlocked(true)
    _ = blocker.setBlocked(true)
    #expect(assertion.creates == [.test, .test])
    #expect(assertion.liveCount == 1)
    #expect(assertion.releaseCalls == 0)
    #expect(clamshell.calls == [true, true])
    #expect(blocker.isBlocking == true)
    _ = blocker.setBlocked(false)
    #expect(assertion.liveCount == 0)
    #expect(assertion.releaseCalls == 1)
    #expect(blocker.isBlocking == false)
}

@Test func blockerReleasesAndClearsOnUnblock() {
    let assertion = FakeIdleAssertion()
    let clamshell = FakeClamshell()
    let blocker = SleepBlocker(assertion: assertion, clamshell: clamshell, descriptor: .test)
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
    let blocker = SleepBlocker(assertion: assertion, clamshell: clamshell, descriptor: .test)
    let report = blocker.setBlocked(false)
    #expect(report.state == SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: false))
    #expect(assertion.releaseCalls == 1)
    #expect(clamshell.calls == [false])
}

@Test(arguments: [
    PmsetRunResult.exited(status: 1, stderr: "needs root"),
    PmsetRunResult.watchdogTimedOut(stderr: ""),
    PmsetRunResult.launchFailed(message: "ENOENT"),
])
func blockerPmsetFailureLeavesUnsettledUnknown(failure: PmsetRunResult) {
    let clamshell = FakeClamshell()
    clamshell.result = failure
    let blocker = SleepBlocker(assertion: FakeIdleAssertion(), clamshell: clamshell, descriptor: .test)
    let report = blocker.setBlocked(true)
    #expect(report.state == SleepBlockState(desired: true, assertionHeld: true, pmsetDisableSleep: nil))
    #expect(report.state.isSettled == false)
    #expect(report.pmset == failure)
    #expect(blocker.isBlocking == false)
}

@Test func blockerAssertionFailureLeavesUnsettled() {
    let assertion = FakeIdleAssertion()
    assertion.createResult = false
    let blocker = SleepBlocker(assertion: assertion, clamshell: FakeClamshell(), descriptor: .test)
    let report = blocker.setBlocked(true)
    #expect(report.state == SleepBlockState(desired: true, assertionHeld: false, pmsetDisableSleep: true))
    #expect(report.state.isSettled == false)
    #expect(blocker.isBlocking == false)
}

@Test func clearUntilSettledRetriesTransientPmsetFailure() {
    let clamshell = SequencedClamshell([
        .exited(status: 1, stderr: "resource busy"),
        .exited(status: 0, stderr: ""),
    ])
    let blocker = SleepBlocker(assertion: FakeIdleAssertion(), clamshell: clamshell, descriptor: .test)
    var naps = 0
    let (report, attempts) = blocker.clearUntilSettled(maxAttempts: 4, nap: { _ in naps += 1 })
    #expect(attempts == 2)
    #expect(naps == 1)
    #expect(report.state.isSettled == true)
    #expect(report.state.pmsetDisableSleep == false)
    #expect(clamshell.calls == [false, false])
    #expect(blocker.isBlocking == false)
}

@Test func clearUntilSettledStopsAtBudgetWhenNeverSettling() {
    let clamshell = SequencedClamshell([.launchFailed(message: "ENOENT")])
    let blocker = SleepBlocker(assertion: FakeIdleAssertion(), clamshell: clamshell, descriptor: .test)
    var naps = 0
    let (report, attempts) = blocker.clearUntilSettled(maxAttempts: 3, nap: { _ in naps += 1 })
    #expect(attempts == 3)
    #expect(naps == 2)
    #expect(report.state.isSettled == false)
    #expect(clamshell.calls == [false, false, false])
}

@Test func needsClearStartsTrueAndClearsWhenBootClearSettles() {
    let clamshell = SequencedClamshell([
        .exited(status: 1, stderr: "resource busy"),
        .exited(status: 0, stderr: ""),
    ])
    let blocker = SleepBlocker(assertion: FakeIdleAssertion(), clamshell: clamshell, descriptor: .test)
    #expect(blocker.needsClear == true)
    let (report, attempts) = blocker.clearUntilSettled(maxAttempts: 4, nap: { _ in })
    #expect(attempts == 2)
    #expect(report.state.isSettled == true)
    #expect(blocker.needsClear == false)
}

@Test func needsClearStaysTrueWhenBootClearNeverSettles() {
    let clamshell = SequencedClamshell([.launchFailed(message: "ENOENT")])
    let blocker = SleepBlocker(assertion: FakeIdleAssertion(), clamshell: clamshell, descriptor: .test)
    let (report, attempts) = blocker.clearUntilSettled(maxAttempts: 4, nap: { _ in })
    #expect(attempts == 4)
    #expect(report.state.isSettled == false)
    #expect(blocker.needsClear == true)
}
