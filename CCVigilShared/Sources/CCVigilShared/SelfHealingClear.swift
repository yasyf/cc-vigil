public final class SelfHealingClear: Sendable {
    public static let retrySeconds = 5.0

    private let attemptClear: @Sendable () -> Bool
    private let isArmed: @Sendable () -> Bool
    private let scheduleRetry: @Sendable (@escaping @Sendable () -> Void) -> Void

    public init(
        attemptClear: @escaping @Sendable () -> Bool,
        isArmed: @escaping @Sendable () -> Bool,
        scheduleRetry: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void
    ) {
        self.attemptClear = attemptClear
        self.isArmed = isArmed
        self.scheduleRetry = scheduleRetry
    }

    public func fire() {
        guard isArmed() else { return }
        guard attemptClear() else {
            scheduleRetry { [self] in fire() }
            return
        }
    }
}
