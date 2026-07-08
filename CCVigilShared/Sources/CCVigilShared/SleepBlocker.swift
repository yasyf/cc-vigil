import os

public protocol IdleAssertionControlling: AnyObject {
    func create() -> Bool
    func release()
}

public struct SleepBlockReport: Equatable, Sendable {
    public let state: SleepBlockState
    public let pmset: PmsetRunResult

    public init(state: SleepBlockState, pmset: PmsetRunResult) {
        self.state = state
        self.pmset = pmset
    }
}

public final class SleepBlocker: Sendable {
    private struct Mechanisms {
        var policy: SleepBlockPolicy
        let assertion: any IdleAssertionControlling
        let clamshell: any ClamshellControlling
    }

    private let mechanisms: OSAllocatedUnfairLock<Mechanisms>

    public init(assertion: any IdleAssertionControlling, clamshell: any ClamshellControlling) {
        mechanisms = OSAllocatedUnfairLock(uncheckedState: Mechanisms(
            policy: SleepBlockPolicy(),
            assertion: assertion,
            clamshell: clamshell
        ))
    }

    public var isBlocking: Bool {
        mechanisms.withLockUnchecked { $0.policy.isBlocking }
    }

    public var state: SleepBlockState {
        mechanisms.withLockUnchecked { $0.policy.state }
    }

    public func setBlocked(_ blocked: Bool) -> SleepBlockReport {
        mechanisms.withLockUnchecked { guarded in
            var pmsetResult: PmsetRunResult?
            for action in guarded.policy.set(blocked) {
                switch action {
                case .createAssertion:
                    guarded.policy.record(.assertionCreated(success: guarded.assertion.create()))
                case .releaseAssertion:
                    guarded.assertion.release()
                    guarded.policy.record(.assertionReleased)
                case let .setPmsetDisableSleep(disableSleep):
                    let result = guarded.clamshell.setDisableSleep(disableSleep)
                    pmsetResult = result
                    guarded.policy.record(.pmsetCompleted(
                        disableSleep: disableSleep,
                        success: result.succeeded
                    ))
                }
            }
            guard let pmsetResult else {
                preconditionFailure("SleepBlockPolicy.set emitted no pmset action")
            }
            return SleepBlockReport(state: guarded.policy.state, pmset: pmsetResult)
        }
    }
}
