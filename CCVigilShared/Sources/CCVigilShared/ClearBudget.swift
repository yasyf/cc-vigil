import Foundation

/// The end-to-end time budget for a confirmed sleep-block `.clear`, shared so the
/// daemon's confirm loop, the CLI socket handler, and the app's socket client all
/// size their timeouts from one source. A slow pmset can make the daemon spend up
/// to `attempts × helperCallSeconds` confirming the clear; the socket handler and
/// the client each sit strictly above that so a slow-but-progressing clear is
/// never cut short mid-confirmation — the block is cleared while the helper is
/// still registered, not left behind a SIGKILL-truncatable shutdown handler.
public enum ClearBudget {
    /// Retries in the daemon's confirmed-clear loop.
    public static let attempts = 4
    /// Ceiling on a single helper `setSleepBlocked` XPC push.
    public static let helperCallSeconds = 15.0
    public static let daemonWorstCaseSeconds = Double(attempts) * helperCallSeconds
    public static let socketHandlerSeconds = daemonWorstCaseSeconds + 10
    public static let clientSeconds = Int(socketHandlerSeconds) + 10
}
