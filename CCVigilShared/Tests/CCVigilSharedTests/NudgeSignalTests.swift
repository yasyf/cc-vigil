import CCVigilShared
import Testing

@Test func pendingNudgeReturnsImmediately() async {
    let signal = NudgeSignal()
    await signal.nudge()
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        await signal.wait(upTo: 10)
    }
    #expect(elapsed < .seconds(1))
}

@Test func waitTimesOutWithoutNudge() async {
    let signal = NudgeSignal()
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        await signal.wait(upTo: 0.05)
    }
    #expect(elapsed >= .milliseconds(45))
    #expect(elapsed < .seconds(5))
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
    #expect(elapsed < .seconds(10))
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
