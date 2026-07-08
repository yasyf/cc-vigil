public actor NudgeSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var pending = false
    private var waitGeneration: UInt64 = 0

    public init() {}

    public func nudge() {
        guard let continuation else {
            pending = true
            return
        }
        self.continuation = nil
        continuation.resume()
    }

    public func wait(upTo seconds: Double) async {
        precondition(continuation == nil, "NudgeSignal supports a single waiter")
        if pending {
            pending = false
            return
        }
        waitGeneration &+= 1
        let generation = waitGeneration
        var timeout: Task<Void, Never>?
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            continuation = waiter
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.timeoutFired(generation: generation)
            }
        }
        timeout?.cancel()
    }

    private func timeoutFired(generation: UInt64) {
        guard generation == waitGeneration, let continuation else { return }
        self.continuation = nil
        continuation.resume()
    }
}
