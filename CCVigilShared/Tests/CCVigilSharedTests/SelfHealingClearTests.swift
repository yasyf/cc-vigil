import CCVigilShared
import Foundation
import os
import Testing

private final class NoopAssertion: IdleAssertionControlling {
    func create() -> Bool {
        true
    }

    func release() {}
}

private final class SequencedClamshell: ClamshellControlling, @unchecked Sendable {
    private let results: OSAllocatedUnfairLock<[PmsetRunResult]>
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    init(_ results: [PmsetRunResult]) {
        self.results = OSAllocatedUnfairLock(initialState: results)
    }

    var callCount: Int {
        calls.withLock { $0 }
    }

    func setDisableSleep(_: Bool) -> PmsetRunResult {
        calls.withLock { $0 += 1 }
        return results.withLock { $0.isEmpty ? .exited(status: 0, stderr: "") : $0.removeFirst() }
    }
}

@Test func fireStopsWhenClearConfirmsImmediately() {
    let attempts = OSAllocatedUnfairLock(initialState: 0)
    let schedules = OSAllocatedUnfairLock(initialState: 0)
    SelfHealingClear(
        attemptClear: { attempts.withLock { $0 += 1 }; return true },
        isArmed: { true },
        scheduleRetry: { _ in schedules.withLock { $0 += 1 } }
    ).fire()
    #expect(attempts.withLock { $0 } == 1)
    #expect(schedules.withLock { $0 } == 0)
}

@Test func fireRetriesUntilClearConfirms() {
    let outcomes = [false, false, true]
    let attempts = OSAllocatedUnfairLock(initialState: 0)
    let schedules = OSAllocatedUnfairLock(initialState: 0)
    SelfHealingClear(
        attemptClear: {
            let attempt = attempts.withLock { $0 += 1; return $0 }
            return outcomes[attempt - 1]
        },
        isArmed: { true },
        scheduleRetry: { work in schedules.withLock { $0 += 1 }; work() }
    ).fire()
    #expect(attempts.withLock { $0 } == 3)
    #expect(schedules.withLock { $0 } == 2)
}

@Test func fireStopsRetryingOnceDisarmed() {
    let attempts = OSAllocatedUnfairLock(initialState: 0)
    let armedCalls = OSAllocatedUnfairLock(initialState: 0)
    SelfHealingClear(
        attemptClear: { attempts.withLock { $0 += 1 }; return false },
        isArmed: { armedCalls.withLock { $0 += 1; return $0 } == 1 },
        scheduleRetry: { work in work() }
    ).fire()
    #expect(attempts.withLock { $0 } == 1)
}

@Test func fireSkipsClearWhenDisarmedUpFront() {
    let attempts = OSAllocatedUnfairLock(initialState: 0)
    SelfHealingClear(
        attemptClear: { attempts.withLock { $0 += 1 }; return true },
        isArmed: { false },
        scheduleRetry: { work in work() }
    ).fire()
    #expect(attempts.withLock { $0 } == 0)
}

@Test func selfHealingClearConfirmsAfterPmsetFailsOnce() {
    let clamshell = SequencedClamshell([
        .exited(status: 1, stderr: "needs root"),
        .exited(status: 0, stderr: ""),
    ])
    let blocker = SleepBlocker(assertion: NoopAssertion(), clamshell: clamshell)
    let schedules = OSAllocatedUnfairLock(initialState: 0)
    SelfHealingClear(
        attemptClear: { blocker.setBlocked(false).state.isSettled },
        isArmed: { true },
        scheduleRetry: { work in schedules.withLock { $0 += 1 }; work() }
    ).fire()
    #expect(clamshell.callCount == 2)
    #expect(schedules.withLock { $0 } == 1)
    #expect(blocker.state == SleepBlockState(desired: false, assertionHeld: false, pmsetDisableSleep: false))
    #expect(blocker.state.isSettled == true)
}
