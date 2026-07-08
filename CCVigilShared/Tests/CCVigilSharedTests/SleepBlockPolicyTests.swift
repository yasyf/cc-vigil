import CCVigilShared
import Testing

@Test func policyInitNeedsCrashRecoveryClear() {
    let policy = SleepBlockPolicy()
    #expect(policy.desired == false)
    #expect(policy.assertionHeld == false)
    #expect(policy.pmset == .unknown)
    #expect(policy.needsClear == true)
    #expect(policy.isBlocking == false)
    #expect(policy.state == SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: nil))
    #expect(policy.state.isSettled == false)
}

@Test func policySetTrueEmitsFullMechanism() {
    var policy = SleepBlockPolicy()
    let actions = policy.set(true)
    #expect(actions == [.createAssertion, .setPmsetDisableSleep(true)])
    #expect(policy.desired == true)
}

@Test func policySetFalseEmitsFullClear() {
    var policy = SleepBlockPolicy()
    let actions = policy.set(false)
    #expect(actions == [.releaseAssertion, .setPmsetDisableSleep(false)])
    #expect(policy.desired == false)
}

@Test func policySetTrueRerunsDeliberatelyWhenAlreadyBlocking() {
    var policy = SleepBlockPolicy()
    _ = policy.set(true)
    policy.record(.assertionCreated(success: true))
    policy.record(.pmsetCompleted(disableSleep: true, success: true))
    #expect(policy.isBlocking == true)
    let reissued = policy.set(true)
    #expect(reissued == [.createAssertion, .setPmsetDisableSleep(true)])
}

@Test func policySetFalseForceClearsEvenWhenAlreadyClear() {
    var policy = SleepBlockPolicy()
    _ = policy.set(false)
    policy.record(.assertionReleased)
    policy.record(.pmsetCompleted(disableSleep: false, success: true))
    #expect(policy.state.isSettled == true)
    let reissued = policy.set(false)
    #expect(reissued == [.releaseAssertion, .setPmsetDisableSleep(false)])
}

@Test func policyBlockLifecycleComposesOutcomes() {
    var policy = SleepBlockPolicy()
    _ = policy.set(true)
    policy.record(.assertionCreated(success: true))
    #expect(policy.isBlocking == false)
    policy.record(.pmsetCompleted(disableSleep: true, success: true))
    #expect(policy.isBlocking == true)
    #expect(policy.needsClear == false)
    #expect(policy.state == SleepBlockState(desired: true, assertionHeld: true, pmsetDisableSleep: true))
    #expect(policy.state.isSettled == true)
}

@Test func policyClearLifecycleSettles() {
    var policy = SleepBlockPolicy()
    _ = policy.set(true)
    policy.record(.assertionCreated(success: true))
    policy.record(.pmsetCompleted(disableSleep: true, success: true))
    _ = policy.set(false)
    policy.record(.assertionReleased)
    policy.record(.pmsetCompleted(disableSleep: false, success: true))
    #expect(policy.isBlocking == false)
    #expect(policy.needsClear == false)
    #expect(policy.state == SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: false))
    #expect(policy.state.isSettled == true)
}

@Test func policyAssertionFailureLeavesNotBlocking() {
    var policy = SleepBlockPolicy()
    _ = policy.set(true)
    policy.record(.assertionCreated(success: false))
    policy.record(.pmsetCompleted(disableSleep: true, success: true))
    #expect(policy.assertionHeld == false)
    #expect(policy.isBlocking == false)
    #expect(policy.state.isSettled == false)
}

@Test func policyPmsetFailureDemandsClearAgain() {
    var policy = SleepBlockPolicy()
    _ = policy.set(true)
    policy.record(.assertionCreated(success: true))
    policy.record(.pmsetCompleted(disableSleep: true, success: false))
    #expect(policy.pmset == .unknown)
    #expect(policy.needsClear == true)
    #expect(policy.isBlocking == false)
    #expect(policy.state == SleepBlockState(desired: true, assertionHeld: true, pmsetDisableSleep: nil))
}

@Test(arguments: [
    (PmsetApplied.unknown, Bool?.none),
    (PmsetApplied.disableSleep(true), Bool?(true)),
    (PmsetApplied.disableSleep(false), Bool?(false)),
])
func pmsetAppliedExposesKnownValue(applied: PmsetApplied, expected: Bool?) {
    #expect(applied.knownDisableSleep == expected)
}

@Test func sleepBlockStateSettledRequiresDesiredLegsToAgree() {
    #expect(SleepBlockState(desired: true, assertionHeld: true, pmsetDisableSleep: true).isSettled == true)
    #expect(SleepBlockState(desired: true, assertionHeld: false, pmsetDisableSleep: true).isSettled == false)
    #expect(SleepBlockState(desired: true, assertionHeld: true, pmsetDisableSleep: false).isSettled == false)
    #expect(SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: false).isSettled == true)
    #expect(SleepBlockState(desired: false, assertionHeld: true, pmsetDisableSleep: false).isSettled == false)
    #expect(SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: nil).isSettled == false)
}
