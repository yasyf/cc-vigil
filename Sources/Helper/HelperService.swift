import CCVigilShared
import Foundation
import os

extension Logger {
    static let helper = Logger(subsystem: "dev.yasyf.cc-vigil", category: "Helper")
}

final class HelperService: NSObject, HelperXPCProtocol, @unchecked Sendable {
    private let blocker: SleepBlocker
    private let helperVersion: String

    init(blocker: SleepBlocker, version: String) {
        self.blocker = blocker
        helperVersion = version
    }

    func setSleepBlocked(_ blocked: Bool, reply: @escaping @Sendable (Bool, NSError?) -> Void) {
        let report = blocker.setBlocked(blocked)
        let applied = report.state.desired
            && report.state.assertionHeld
            && report.state.pmsetDisableSleep == true
        if report.state.isSettled {
            Logger.helper.info(
                "setSleepBlocked(\(blocked, privacy: .public)) settled; blocking=\(applied, privacy: .public)"
            )
            reply(applied, nil)
        } else {
            let detail = describe(report)
            Logger.helper.error(
                "setSleepBlocked(\(blocked, privacy: .public)) unsettled: \(detail, privacy: .public)"
            )
            reply(applied, NSError(domain: HelperXPC.errorDomain, code: 1, userInfo: [
                NSLocalizedDescriptionKey: "sleep block unsettled: \(detail)",
            ]))
        }
    }

    func sleepBlockedState(reply: @escaping @Sendable (Bool) -> Void) {
        reply(blocker.isBlocking)
    }

    func version(reply: @escaping @Sendable (String) -> Void) {
        reply(helperVersion)
    }

    private func describe(_ report: SleepBlockReport) -> String {
        "desired=\(report.state.desired) assertionHeld=\(report.state.assertionHeld) "
            + "pmsetDisableSleep=\(String(describing: report.state.pmsetDisableSleep)) "
            + "pmset=\(String(describing: report.pmset))"
    }
}
