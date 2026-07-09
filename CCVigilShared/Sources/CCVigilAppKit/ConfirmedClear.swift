/// The outcome of the uninstall's `.clear` round-trip, injected so the retry
/// policy stays testable without the daemon-socket edge.
public enum ClearAttempt: Sendable {
    /// The daemon acked a settled clear.
    case confirmed
    /// The daemon replied that the block would not settle.
    case wedged
    /// No reply within the clear budget — the daemon may still be settling.
    case timedOut
    /// The daemon could not be reached.
    case unreachable
}

/// Confirms the sleep block is clear before uninstall unregisters the services.
/// A timed-out clear is ambiguous — the daemon may still be settling a slow
/// pmset — so it polls `.status` once before giving up and letting the caller
/// proceed on the loud-log path; a wedged or unreachable daemon is genuinely
/// unconfirmed and short-circuits straight to that fall-through.
public struct ConfirmedClear: Sendable {
    let attemptClear: @Sendable () async -> ClearAttempt
    let pollBlockCleared: @Sendable () async -> Bool

    public init(
        attemptClear: @escaping @Sendable () async -> ClearAttempt,
        pollBlockCleared: @escaping @Sendable () async -> Bool
    ) {
        self.attemptClear = attemptClear
        self.pollBlockCleared = pollBlockCleared
    }

    public func run() async -> Bool {
        switch await attemptClear() {
        case .confirmed:
            true
        case .timedOut:
            await pollBlockCleared()
        case .wedged, .unreachable:
            false
        }
    }
}
