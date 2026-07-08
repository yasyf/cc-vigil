import Dispatch
import Foundation
import os

public enum PmsetCommand {
    public static let executablePath = "/usr/bin/pmset"

    public static func arguments(disableSleep: Bool) -> [String] {
        ["-a", "disablesleep", disableSleep ? "1" : "0"]
    }
}

public enum PmsetRunResult: Equatable, Sendable {
    case exited(status: Int32, stderr: String)
    case watchdogTimedOut(stderr: String)
    case launchFailed(message: String)

    public var succeeded: Bool {
        switch self {
        case let .exited(status, _): status == 0
        case .watchdogTimedOut, .launchFailed: false
        }
    }
}

public protocol PmsetProcessHandle: AnyObject {
    func launch(
        stderrSink: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws
    func terminate()
}

public protocol PmsetLaunching {
    func makeProcess(disableSleep: Bool) -> any PmsetProcessHandle
}

public protocol ClamshellControlling {
    func setDisableSleep(_ disableSleep: Bool) -> PmsetRunResult
}

public final class PmsetClamshellControl: ClamshellControlling {
    public static let watchdogSeconds = 10.0

    private let launcher: any PmsetLaunching
    private let timeoutSeconds: Double

    public init(
        launcher: any PmsetLaunching,
        timeoutSeconds: Double = PmsetClamshellControl.watchdogSeconds
    ) {
        self.launcher = launcher
        self.timeoutSeconds = timeoutSeconds
    }

    public func setDisableSleep(_ disableSleep: Bool) -> PmsetRunResult {
        let process = launcher.makeProcess(disableSleep: disableSleep)
        let stderr = OSAllocatedUnfairLock(initialState: Data())
        let exitStatus = OSAllocatedUnfairLock<Int32?>(initialState: nil)
        let exited = DispatchSemaphore(value: 0)
        do {
            try process.launch(
                stderrSink: { chunk in stderr.withLock { $0.append(chunk) } },
                onExit: { status in
                    exitStatus.withLock { $0 = status }
                    exited.signal()
                }
            )
        } catch {
            return .launchFailed(message: String(describing: error))
        }
        guard exited.wait(timeout: .now() + timeoutSeconds) == .success else {
            process.terminate()
            // Reap the terminated child before returning: a still-running pmset
            // could otherwise finish after the next serialized `disablesleep`
            // call and clobber it (re-strand disablesleep at 1).
            _ = exited.wait(timeout: .now() + timeoutSeconds)
            return .watchdogTimedOut(stderr: drained(stderr))
        }
        guard let status = exitStatus.withLock({ $0 }) else {
            preconditionFailure("pmset exit signaled without a status")
        }
        return .exited(status: status, stderr: drained(stderr))
    }

    private func drained(_ stderr: OSAllocatedUnfairLock<Data>) -> String {
        // swiftlint:disable:next optional_data_string_conversion - deliberate lossy decode of diagnostic stderr
        String(decoding: stderr.withLock { $0 }, as: UTF8.self)
    }
}
