/// Tracks whether an uninstall `.clear` has latched the daemon fail-open. The
/// clear is sticky on purpose — the block must stay released across the teardown
/// — but a *stray* same-user clear outside an uninstall would otherwise pin the
/// daemon fail-open until restart. A real uninstall boots the daemon in silence
/// moments after the clear, so any subsequent active work or control op means it
/// was not an uninstall: that traffic un-latches. Passive probes (`.status`,
/// `.ping`) leave the latch untouched, so the uninstall clear-confirm retry can
/// poll `.status` without un-latching a genuine teardown.
public struct ClearLatch: Sendable {
    public private(set) var isClearing: Bool

    public init(isClearing: Bool = false) {
        self.isClearing = isClearing
    }

    public mutating func fold(_ request: WireRequest) {
        switch request {
        case .clear:
            isClearing = true
        case .nudge, .hold, .release, .pause:
            isClearing = false
        case .status, .ping:
            break
        }
    }
}
