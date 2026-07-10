import Foundation

/// Persists how many "Repair Background Services" attempts have failed to register
/// every service in a row, so the sfltool-resetbtm hint survives across app
/// restarts. Mirrors the UserDefaults watermark store: a key on the standard
/// suite, zero-defaulting because a fresh install has no failures behind it.
public protocol RepairFailureCountStore: AnyObject, Sendable {
    var consecutiveFailures: Int { get }
    func record(_ count: Int)
}

public final class UserDefaultsRepairFailureCountStore: RepairFailureCountStore, @unchecked Sendable {
    private static let key = "repairConsecutiveFailures"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var consecutiveFailures: Int {
        defaults.integer(forKey: Self.key)
    }

    public func record(_ count: Int) {
        defaults.set(count, forKey: Self.key)
    }
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
