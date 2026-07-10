import CCVigilAppKit
import Foundation
import Testing

private let hint =
    "If registration keeps failing, run 'sfltool resetbtm' in Terminal and retry"
        + " — macOS occasionally wedges background-item registration."

private let failLines = [
    "dev.yasyf.cc-vigil.daemon.plist: not permitted",
    "dev.yasyf.cc-vigil.helper.plist: registered",
]

private let successLines = [
    "dev.yasyf.cc-vigil.daemon.plist: registered",
    "dev.yasyf.cc-vigil.helper.plist: registered",
]

private final class FakeRepairFailureCountStore: RepairFailureCountStore, @unchecked Sendable {
    private(set) var consecutiveFailures: Int

    init(consecutiveFailures: Int = 0) {
        self.consecutiveFailures = consecutiveFailures
    }

    func record(_ count: Int) {
        consecutiveFailures = count
    }
}

/// The first failure only counts — one wedged registration is common and clears
/// on its own, so surfacing the sfltool escape hatch that early is noise.
@Test func firstFailureCountsButSurfacesNoHint() {
    let store = FakeRepairFailureCountStore()
    let message = RepairHintTracker(store: store).message(succeeded: false, lines: failLines)
    #expect(message == failLines.joined(separator: "\n"))
    #expect(store.consecutiveFailures == 1)
}

/// The second consecutive failure is the signal that registration is genuinely
/// wedged; the message gains exactly the resetbtm sentence, appended to the lines.
@Test func secondConsecutiveFailureAppendsResetbtmHint() {
    let store = FakeRepairFailureCountStore(consecutiveFailures: 1)
    let message = RepairHintTracker(store: store).message(succeeded: false, lines: failLines)
    #expect(message == failLines.joined(separator: "\n") + "\n\n" + hint)
    #expect(store.consecutiveFailures == 2)
}

/// Failures past the second keep the hint — "keeps failing" — and keep counting.
@Test func failuresPastTheSecondKeepTheHint() {
    let store = FakeRepairFailureCountStore(consecutiveFailures: 4)
    let message = RepairHintTracker(store: store).message(succeeded: false, lines: failLines)
    #expect(message.hasSuffix(hint))
    #expect(store.consecutiveFailures == 5)
}

/// A success clears the streak and drops the hint, so the counter must be back at
/// zero for the next attempt.
@Test func successResetsTheCounterAndDropsTheHint() {
    let store = FakeRepairFailureCountStore(consecutiveFailures: 3)
    let message = RepairHintTracker(store: store).message(succeeded: true, lines: successLines)
    #expect(message == successLines.joined(separator: "\n"))
    #expect(store.consecutiveFailures == 0)
}

/// After a success interrupts a streak, it again takes two consecutive failures to
/// re-earn the hint — the counter is consecutive, not cumulative.
@Test func hintIsConsecutiveNotCumulative() {
    let store = FakeRepairFailureCountStore()
    let tracker = RepairHintTracker(store: store)
    _ = tracker.message(succeeded: false, lines: failLines)
    _ = tracker.message(succeeded: true, lines: successLines)
    let afterReset = tracker.message(succeeded: false, lines: failLines)
    #expect(!afterReset.contains("sfltool resetbtm"))
    #expect(store.consecutiveFailures == 1)
}
