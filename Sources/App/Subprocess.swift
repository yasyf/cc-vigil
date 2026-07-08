import Foundation

enum BundledCLI {
    static var url: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cc-vigil")
    }

    static func run(_ arguments: [String]) async -> (status: Int32, output: String) {
        await Subprocess.run(executable: url, arguments: arguments)
    }
}

enum Subprocess {
    static func run(executable: URL, arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                // swiftlint:disable:next optional_data_string_conversion - tool output is best-effort text
                let output = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: (finished.terminationStatus, output))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, String(describing: error)))
            }
        }
    }
}
