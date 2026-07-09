import Dispatch

/// Bounds how many connections a socket server serves at once. `admit` blocks the
/// accept thread once `limit` slots are taken, so a burst of same-user clients
/// queues in the kernel backlog instead of spawning unbounded concurrent
/// handlers; each slot frees when its work returns.
public final class ConnectionThrottle: @unchecked Sendable {
    private let slots: DispatchSemaphore
    private let queue: DispatchQueue

    public init(limit: Int, queue: DispatchQueue) {
        precondition(limit > 0, "connection limit must be positive")
        slots = DispatchSemaphore(value: limit)
        self.queue = queue
    }

    public func admit(_ work: @escaping @Sendable () -> Void) {
        slots.wait()
        queue.async { [slots] in
            defer { slots.signal() }
            work()
        }
    }
}
