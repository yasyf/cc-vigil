import CCVigilShared
import Dispatch
import Foundation
import os
import Testing

private func waitUntil(_ seconds: TimeInterval = 30, _ predicate: () -> Bool) -> Bool {
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

    // Best-effort (NOT an assertion — result discarded): give the first `limit`
    // work items up to 2s to park inside admit() so the peak builds toward the
    // limit and would expose an over-admitting throttle. A starved GCD pool may
    // not schedule them in time; that's fine, the guarantee below still holds.
    _ = waitUntil(2) { state.withLock { $0.current } == limit }
    for _ in 0 ..< clients {
        release.signal()
    }
    // The throttle's contract is: every client served, and never more than
    // `limit` running at once. Assert exactly that — not that the peak *reaches*
    // the limit, which needs the GCD pool to run `limit` closures simultaneously
    // (a starved runner won't, and left peak at 0 within the old 2s window). The
    // 30s ceiling is generous; a healthy run returns early.
    #expect(waitUntil { state.withLock { $0.done } == clients })
    #expect(state.withLock { $0.peak } <= limit)
}
