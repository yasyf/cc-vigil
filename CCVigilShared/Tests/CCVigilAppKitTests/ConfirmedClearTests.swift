import CCVigilAppKit
import Testing

private actor CallCounter {
    private(set) var polls = 0

    func poll(_ result: Bool) -> Bool {
        polls += 1
        return result
    }
}

@Test func confirmedClearAcksWithoutPolling() async {
    let counter = CallCounter()
    let clear = ConfirmedClear(
        attemptClear: { .confirmed },
        pollBlockCleared: { await counter.poll(true) }
    )
    #expect(await clear.run())
    #expect(await counter.polls == 0)
}

@Test func timedOutClearPollsStatusAndConfirmsWhenTheBlockIsGone() async {
    let counter = CallCounter()
    let clear = ConfirmedClear(
        attemptClear: { .timedOut },
        pollBlockCleared: { await counter.poll(true) }
    )
    #expect(await clear.run())
    #expect(await counter.polls == 1)
}

@Test func timedOutClearFallsThroughWhenStatusStillShowsTheBlock() async {
    let counter = CallCounter()
    let clear = ConfirmedClear(
        attemptClear: { .timedOut },
        pollBlockCleared: { await counter.poll(false) }
    )
    #expect(await clear.run() == false)
    #expect(await counter.polls == 1)
}

@Test(arguments: [ClearAttempt.wedged, .unreachable])
func unconfirmedClearNeverPollsAndDoesNotConfirm(attempt: ClearAttempt) async {
    let counter = CallCounter()
    let clear = ConfirmedClear(
        attemptClear: { attempt },
        pollBlockCleared: { await counter.poll(true) }
    )
    #expect(await clear.run() == false)
    #expect(await counter.polls == 0)
}
