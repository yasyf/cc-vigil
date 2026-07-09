import CCVigilShared
import Testing

@Test func pendingNudgeReturnsImmediately() async {
    let signal = NudgeSignal()
    await signal.nudge()
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        await signal.wait(upTo: 10)
    }
    // Consuming a pending nudge returns synchronously (no continuation, so not
    // subject to the scheduler starvation that inflates the timeout path). The
    // ceiling only guards against it wrongly blocking to the `upTo:` timeout, so
    // a value well under 10s and above scheduling jitter suffices.
    #expect(elapsed < .seconds(5))
}

@Test(.timeLimit(.minutes(1)))
func waitTimesOutWithoutNudge() async {
    let signal = NudgeSignal()
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        await signal.wait(upTo: 0.05)
    }
    // Lower bound only: the wait must block for ~its timeout (it returned late,
    // not instantly). No wall-clock ceiling — under parallel test load the
    // continuation can resume seconds late (this 50ms wait measured 5.8s on a CI
    // runner), so a tight upper bound tests the scheduler, not NudgeSignal. The
    // `.timeLimit` trait catches a genuine hang.
    #expect(elapsed >= .milliseconds(45))
}

@Test func nudgeDuringWaitResumesEarly() async {
    let signal = NudgeSignal()
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        async let waiter: Void = signal.wait(upTo: 30)
        try? await Task.sleep(for: .milliseconds(50))
        await signal.nudge()
        await waiter
    }
    // A generous ceiling below the 30s `upTo:` timeout: the nudge resumes the
    // waiter almost immediately, but a starved runner can delay the continuation
    // resume by several seconds. Stay under 30s so a never-resumed regression
    // (which would hit the timeout) still fails.
    #expect(elapsed < .seconds(20))
}

@Test func pendingNudgeIsConsumedByOneWait() async {
    let signal = NudgeSignal()
    await signal.nudge()
    await signal.nudge()
    await signal.wait(upTo: 10)
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        await signal.wait(upTo: 0.05)
    }
    #expect(elapsed >= .milliseconds(45))
}
