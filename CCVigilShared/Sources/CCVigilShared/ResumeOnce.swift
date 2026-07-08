import os

public final class ResumeOnce<Value: Sendable>: Sendable {
    private let fired = OSAllocatedUnfairLock(initialState: false)
    private let body: @Sendable (Value) -> Void

    public init(_ body: @escaping @Sendable (Value) -> Void) {
        self.body = body
    }

    @discardableResult
    public func callAsFunction(_ value: Value) -> Bool {
        let first = fired.withLock { alreadyFired in
            guard !alreadyFired else { return false }
            alreadyFired = true
            return true
        }
        if first {
            body(value)
        }
        return first
    }
}
