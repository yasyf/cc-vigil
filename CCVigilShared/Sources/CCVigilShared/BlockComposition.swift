/// Composes the daemon's block intent from the oracle decision, active holds,
/// and the three release overrides. A block is desired when the oracle says to
/// block or a hold is active — unless a pause, a cutout latch, or an in-flight
/// uninstall clear forces the block off. The overrides win unconditionally so
/// the Mac can always sleep when a human paused it, a cutout tripped, or the
/// daemon is tearing down.
public struct BlockComposition: Equatable, Sendable {
    public let shouldBlock: Bool
    public let hasActiveHolds: Bool
    public let paused: Bool
    public let latchRejectsAcquire: Bool
    public let shuttingDown: Bool

    public init(
        shouldBlock: Bool,
        hasActiveHolds: Bool,
        paused: Bool,
        latchRejectsAcquire: Bool,
        shuttingDown: Bool
    ) {
        self.shouldBlock = shouldBlock
        self.hasActiveHolds = hasActiveHolds
        self.paused = paused
        self.latchRejectsAcquire = latchRejectsAcquire
        self.shuttingDown = shuttingDown
    }

    public var desired: Bool {
        guard !paused, !latchRejectsAcquire, !shuttingDown else { return false }
        return shouldBlock || hasActiveHolds
    }
}
