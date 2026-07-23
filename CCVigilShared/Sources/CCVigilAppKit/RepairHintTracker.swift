import Foundation

/// Persists how many "Repair Background Services" attempts have failed to register
/// every service in a row, so the sfltool-resetbtm hint survives across app
/// restarts.
public protocol RepairFailureCountStore: AnyObject, Sendable {
    var consecutiveFailures: Int { get }
    func record(_ count: Int)
}

/// Folds a repair attempt's outcome into the persisted consecutive-failure count
/// and returns the maintenance message to surface. A success resets the count; a
/// failure increments it, and once two attempts in a row have failed the message
/// gains one line pointing at `sfltool resetbtm` — the usual fix when macOS wedges
/// background-item registration.
public struct RepairHintTracker {
    static let resetbtmHint =
        "If registration keeps failing, run 'sfltool resetbtm' in Terminal and retry"
            + " — macOS occasionally wedges background-item registration."
    static let hintAfterConsecutiveFailures = 2

    private let store: any RepairFailureCountStore

    public init(store: any RepairFailureCountStore) {
        self.store = store
    }

    public func message(succeeded: Bool, lines: [String]) -> String {
        let base = lines.joined(separator: "\n")
        guard !succeeded else {
            store.record(0)
            return base
        }
        let failures = store.consecutiveFailures + 1
        store.record(failures)
        guard failures >= Self.hintAfterConsecutiveFailures else { return base }
        return base + "\n\n" + Self.resetbtmHint
    }
}
