import CCVigilShared
import Dispatch
import Foundation
import os
import Testing

private func waitUntil(_ seconds: TimeInterval, _ predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if predicate() {
            return true
        }
        Thread.sleep(forTimeInterval: 0.005)
    }
    return predicate()
}

@Test func servesEveryClientButNeverMoreThanTheLimitAtOnce() {
    let limit = 3
    let clients = limit + 1
    let queue = DispatchQueue(label: "throttle-test", attributes: .concurrent)
    let throttle = ConnectionThrottle(limit: limit, queue: queue)

    let state = OSAllocatedUnfairLock(initialState: (current: 0, peak: 0, done: 0))
    let release = DispatchSemaphore(value: 0)

    let admitter = Thread {
        for _ in 0 ..< clients {
            throttle.admit {
                state.withLock {
                    $0.current += 1
                    $0.peak = max($0.peak, $0.current)
                }
                release.wait()
                state.withLock {
                    $0.current -= 1
                    $0.done += 1
                }
            }
        }
    }
    admitter.start()

    // The first `limit` work items park inside admit(); the extra client blocks
    // the admitter until a slot frees, so concurrency tops out at the limit.
    #expect(waitUntil(2) { state.withLock { $0.current } == limit })
    #expect(state.withLock { $0.peak } == limit)

    for _ in 0 ..< clients {
        release.signal()
    }
    #expect(waitUntil(2) { state.withLock { $0.done } == clients })
    #expect(state.withLock { $0.peak } == limit)
}
