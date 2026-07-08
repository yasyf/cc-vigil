import CCVigilShared
import Foundation

final class SystemPmsetProcess: PmsetProcessHandle {
    private let process = Process()

    init(disableSleep: Bool) {
        process.executableURL = URL(fileURLWithPath: PmsetCommand.executablePath)
        process.arguments = PmsetCommand.arguments(disableSleep: disableSleep)
    }

    func launch(
        stderrSink: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrSink(chunk)
            }
        }
        process.terminationHandler = { exited in
            onExit(exited.terminationStatus)
        }
        try process.run()
    }

    func terminate() {
        process.terminate()
    }
}

final class SystemPmsetLauncher: PmsetLaunching {
    func makeProcess(disableSleep: Bool) -> any PmsetProcessHandle {
        SystemPmsetProcess(disableSleep: disableSleep)
    }
}
