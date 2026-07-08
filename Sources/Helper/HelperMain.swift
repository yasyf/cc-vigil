import CCVigilShared
import Dispatch
import Foundation
import os

// Only ad-hoc/dev Helper builds (the Debug config sets CCVIGIL_ADHOC_HELPER_AUTH
// in project.yml) may accept a daemon by signing identifier alone. Release never
// sets the flag, so a Release build whose team-id read returns nil fails closed.
#if CCVIGIL_ADHOC_HELPER_AUTH
    private let allowIdentifierOnlyFallback = true
#else
    private let allowIdentifierOnlyFallback = false
#endif

@main
enum HelperMain {
    static func main() {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            fatalError("CCVigilHelper: CFBundleShortVersionString missing from the embedded Info.plist")
        }
        let blocker = SleepBlocker(
            assertion: IOPMIdleAssertion(),
            clamshell: PmsetClamshellControl(launcher: SystemPmsetLauncher())
        )

        let initialClear = blocker.setBlocked(false)
        Logger.helper.info(
            "init force-clear: pmset=\(String(describing: initialClear.pmset), privacy: .public)"
        )

        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler {
            let (report, attempts) = blocker.clearUntilSettled(
                maxAttempts: 4,
                nap: { _ in Thread.sleep(forTimeInterval: 0.1) }
            )
            Logger.helper.info(
                """
                SIGTERM force-clear: settled=\(report.state.isSettled, privacy: .public) \
                attempts=\(attempts, privacy: .public) \
                pmset=\(String(describing: report.pmset), privacy: .public)
                """
            )
            exit(0)
        }
        sigterm.resume()

        let delegate = HelperListenerDelegate(
            verifier: CallerVerifier(
                clientIdentifier: HelperXPC.daemonIdentifier,
                checker: SecCodeChecker(),
                allowIdentifierOnlyFallback: allowIdentifierOnlyFallback
            ),
            blocker: blocker,
            version: version
        )
        let listener = NSXPCListener(machServiceName: HelperXPC.machServiceName)
        listener.delegate = delegate
        listener.resume()
        Logger.helper.info(
            "CCVigilHelper \(version, privacy: .public) listening on \(HelperXPC.machServiceName, privacy: .public)"
        )

        withExtendedLifetime((sigterm, delegate, listener)) {
            dispatchMain()
        }
    }
}
