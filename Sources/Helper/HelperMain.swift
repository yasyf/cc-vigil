import CCVigilShared
import Dispatch
import Foundation
import os

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
            let report = blocker.setBlocked(false)
            Logger.helper.info(
                "SIGTERM force-clear: pmset=\(String(describing: report.pmset), privacy: .public)"
            )
            exit(0)
        }
        sigterm.resume()

        let delegate = HelperListenerDelegate(
            verifier: CallerVerifier(clientIdentifier: HelperXPC.daemonIdentifier, checker: SecCodeChecker()),
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
