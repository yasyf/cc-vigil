import CCVigilShared
import Dispatch
import Foundation
import os
import Testing

private final class ScriptedPmsetProcess: PmsetProcessHandle, @unchecked Sendable {
    enum Script {
        case exit(status: Int32, stderrChunks: [String])
        case exitInBackground(status: Int32, afterMilliseconds: Int)
        case hang(stderrChunks: [String])
        case hangUntilTerminated(status: Int32, exitAfterMilliseconds: Int)
        case failToLaunch
    }

    struct LaunchError: Error {}

    private let script: Script
    private let capturedOnExit = OSAllocatedUnfairLock<(@Sendable (Int32) -> Void)?>(initialState: nil)
    private let onExitDelivered = OSAllocatedUnfairLock(initialState: false)
    private(set) var terminated = false

    init(script: Script) {
        self.script = script
    }

    var onExitInvoked: Bool {
        onExitDelivered.withLock { $0 }
    }

    func launch(
        stderrSink: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        switch script {
        case .failToLaunch:
            throw LaunchError()
        case let .exit(status, stderrChunks):
            for chunk in stderrChunks {
                stderrSink(Data(chunk.utf8))
            }
            onExit(status)
        case let .exitInBackground(status, afterMilliseconds):
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(afterMilliseconds)) {
                onExit(status)
            }
        case let .hang(stderrChunks):
            for chunk in stderrChunks {
                stderrSink(Data(chunk.utf8))
            }
        case .hangUntilTerminated:
            capturedOnExit.withLock { $0 = onExit }
        }
    }

    func terminate() {
        terminated = true
        guard case let .hangUntilTerminated(status, delayMillis) = script,
              let onExit = capturedOnExit.withLock({ $0 })
        else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delayMillis)) { [onExitDelivered] in
            onExitDelivered.withLock { $0 = true }
            onExit(status)
        }
    }
}

private final class ScriptedPmsetLauncher: PmsetLaunching {
    let process: ScriptedPmsetProcess
    private(set) var requestedDisableSleep: [Bool] = []

    init(process: ScriptedPmsetProcess) {
        self.process = process
    }

    func makeProcess(disableSleep: Bool) -> any PmsetProcessHandle {
        requestedDisableSleep.append(disableSleep)
        return process
    }
}

@Test(arguments: [
    (true, ["-a", "disablesleep", "1"]),
    (false, ["-a", "disablesleep", "0"]),
])
func pmsetCommandArguments(disableSleep: Bool, expected: [String]) {
    #expect(PmsetCommand.arguments(disableSleep: disableSleep) == expected)
    #expect(PmsetCommand.executablePath == "/usr/bin/pmset")
}

@Test(arguments: [
    (PmsetRunResult.exited(status: 0, stderr: ""), true),
    (PmsetRunResult.exited(status: 1, stderr: "boom"), false),
    (PmsetRunResult.watchdogTimedOut(stderr: ""), false),
    (PmsetRunResult.launchFailed(message: ""), false),
])
func pmsetRunResultSuccess(result: PmsetRunResult, expected: Bool) {
    #expect(result.succeeded == expected)
}

@Test func clamshellReportsExitStatusAndDrainedStderr() {
    let process = ScriptedPmsetProcess(script: .exit(status: 0, stderrChunks: ["warn:", " x"]))
    let launcher = ScriptedPmsetLauncher(process: process)
    let control = PmsetClamshellControl(launcher: launcher, timeoutSeconds: 1)
    #expect(control.setDisableSleep(true) == .exited(status: 0, stderr: "warn: x"))
    #expect(launcher.requestedDisableSleep == [true])
    #expect(process.terminated == false)
}

@Test func clamshellReportsNonZeroExit() {
    let process = ScriptedPmsetProcess(script: .exit(status: 1, stderrChunks: ["needs root"]))
    let launcher = ScriptedPmsetLauncher(process: process)
    let control = PmsetClamshellControl(launcher: launcher, timeoutSeconds: 1)
    let result = control.setDisableSleep(false)
    #expect(result == .exited(status: 1, stderr: "needs root"))
    #expect(result.succeeded == false)
    #expect(launcher.requestedDisableSleep == [false])
}

@Test func clamshellWatchdogTerminatesHungPmset() {
    let process = ScriptedPmsetProcess(script: .hang(stderrChunks: ["partial"]))
    let launcher = ScriptedPmsetLauncher(process: process)
    let control = PmsetClamshellControl(launcher: launcher, timeoutSeconds: 0.05)
    #expect(control.setDisableSleep(true) == .watchdogTimedOut(stderr: "partial"))
    #expect(process.terminated == true)
}

@Test func clamshellReapsTerminatedChildBeforeReturning() {
    let process = ScriptedPmsetProcess(script: .hangUntilTerminated(status: 0, exitAfterMilliseconds: 5))
    let launcher = ScriptedPmsetLauncher(process: process)
    let control = PmsetClamshellControl(launcher: launcher, timeoutSeconds: 0.2)
    #expect(control.setDisableSleep(true) == .watchdogTimedOut(stderr: ""))
    #expect(process.terminated == true)
    #expect(process.onExitInvoked == true)
}

@Test func clamshellWaitsForConcurrentExitWithinWatchdog() {
    let process = ScriptedPmsetProcess(script: .exitInBackground(status: 0, afterMilliseconds: 10))
    let launcher = ScriptedPmsetLauncher(process: process)
    let control = PmsetClamshellControl(launcher: launcher, timeoutSeconds: 5)
    #expect(control.setDisableSleep(true) == .exited(status: 0, stderr: ""))
    #expect(process.terminated == false)
}

@Test func clamshellSurfacesLaunchFailure() {
    let process = ScriptedPmsetProcess(script: .failToLaunch)
    let launcher = ScriptedPmsetLauncher(process: process)
    let control = PmsetClamshellControl(launcher: launcher, timeoutSeconds: 1)
    #expect(control.setDisableSleep(true) == .launchFailed(message: "LaunchError()"))
    #expect(process.terminated == false)
}
