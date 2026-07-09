import Foundation

/// Decides when the daemon pushes a desired block state to the helper and folds
/// the push outcome back into its view of the world.
///
/// A push fires on an *edge* (the last pushed desire differs from the current
/// one) or on a periodic *reconcile* while a block is desired. `plan` captures
/// the reassert generation before the caller awaits `push`; `record` takes that
/// captured generation back afterwards. If a `forceReassert` bumped the
/// generation *during* the await — a helper reply-then-crash mid-suspension —
/// `record` leaves `pushedDesired` cleared so the next `plan` re-pushes on an
/// edge instead of suppressing it (the M2 reentrancy hazard).
public struct PushDecider: Equatable, Sendable {
    public struct Plan: Equatable, Sendable {
        public let edge: Bool
        public let reconcile: Bool
        public let generation: Int
    }

    public let reconcileSeconds: TimeInterval

    public private(set) var pushedDesired: Bool?
    public private(set) var lastPushAt: Date
    public private(set) var reassertGeneration: Int

    public init(reconcileSeconds: TimeInterval, lastPushAt: Date = .distantPast) {
        self.reconcileSeconds = reconcileSeconds
        self.lastPushAt = lastPushAt
        pushedDesired = nil
        reassertGeneration = 0
    }

    public func plan(desired: Bool, now: Date) -> Plan? {
        let edge = pushedDesired != desired
        let reconcile = desired && now.timeIntervalSince(lastPushAt) >= reconcileSeconds
        guard edge || reconcile else { return nil }
        return Plan(edge: edge, reconcile: reconcile, generation: reassertGeneration)
    }

    public mutating func record(desired: Bool, settled: Bool, generation: Int, at now: Date) {
        lastPushAt = now
        pushedDesired = settled ? desired : nil
        if generation != reassertGeneration {
            pushedDesired = nil
        }
    }

    public mutating func forceReassert() {
        pushedDesired = nil
        reassertGeneration += 1
    }

    public mutating func resetReconcileClock() {
        lastPushAt = .distantPast
    }
}
