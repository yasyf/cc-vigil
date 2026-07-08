import CCVigilShared
import Testing

@Test func doublesFromOneSecondAndCapsAtThirty() {
    var backoff = Backoff()
    #expect(backoff.next() == 1)
    #expect(backoff.next() == 2)
    #expect(backoff.next() == 4)
    #expect(backoff.next() == 8)
    #expect(backoff.next() == 16)
    #expect(backoff.next() == 30)
    #expect(backoff.next() == 30)
}

@Test func resetReturnsToInitialDelay() {
    var backoff = Backoff()
    _ = backoff.next()
    _ = backoff.next()
    backoff.reset()
    #expect(backoff.next() == 1)
}
