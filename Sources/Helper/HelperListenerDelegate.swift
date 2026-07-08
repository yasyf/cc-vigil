import CCVigilShared
import Dispatch
import Foundation
import os

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let verifier: CallerVerifier
    private let blocker: SleepBlocker
    private let service: HelperService
    private let deadMan = OSAllocatedUnfairLock(initialState: DeadManSwitch())

    init(verifier: CallerVerifier, blocker: SleepBlocker, version: String) {
        self.verifier = verifier
        self.blocker = blocker
        service = HelperService(blocker: blocker, version: version)
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard verifier.shouldAccept(auditToken: newConnection.auditTokenData) else {
            Logger.helper.error(
                "rejected XPC peer pid \(newConnection.processIdentifier, privacy: .public)"
            )
            return false
        }
        deadMan.withLock { $0.connectionOpened() }
        newConnection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [self] in connectionEnded() }
        newConnection.resume()
        Logger.helper.info(
            "accepted daemon connection pid \(newConnection.processIdentifier, privacy: .public)"
        )
        return true
    }

    private var holdsAnyBlock: Bool {
        let state = blocker.state
        return state.desired || !state.isSettled
    }

    private func connectionEnded() {
        let blocked = holdsAnyBlock
        guard let generation = deadMan.withLock({ $0.connectionClosed(whileBlocked: blocked) }) else {
            return
        }
        Logger.helper.info(
            "dead-man armed generation \(generation, privacy: .public): last daemon connection dropped while blocked"
        )
        DispatchQueue.global().asyncAfter(deadline: .now() + DeadManSwitch.graceSeconds) { [self] in
            deadManFired(generation: generation)
        }
    }

    private func deadManFired(generation: UInt64) {
        guard armedToClear(generation: generation) else { return }
        let grace = Int(DeadManSwitch.graceSeconds)
        Logger.helper.fault(
            "dead-man fired: no daemon reconnected within \(grace, privacy: .public)s; force-clearing"
        )
        SelfHealingClear(
            attemptClear: { [self] in attemptDeadManClear() },
            isArmed: { [self] in armedToClear(generation: generation) },
            scheduleRetry: { work in
                DispatchQueue.global().asyncAfter(deadline: .now() + SelfHealingClear.retrySeconds) { work() }
            }
        ).fire()
    }

    private func armedToClear(generation: UInt64) -> Bool {
        deadMan.withLock { $0.shouldClear(firedGeneration: generation) } && holdsAnyBlock
    }

    private func attemptDeadManClear() -> Bool {
        let report = blocker.setBlocked(false)
        let pmset = String(describing: report.pmset)
        if report.state.isSettled {
            Logger.helper.info("dead-man clear confirmed: pmset=\(pmset, privacy: .public)")
            return true
        }
        let detail = "retrying in \(Int(SelfHealingClear.retrySeconds))s: pmset=\(pmset)"
        Logger.helper.fault("dead-man clear unconfirmed, \(detail, privacy: .public)")
        return false
    }
}
