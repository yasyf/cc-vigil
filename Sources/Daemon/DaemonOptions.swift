import CCVigilDaemonKit
import Foundation

struct DaemonOptions {
    static let usage = "usage: CCVigilDaemon [--dry-run] [--transcripts-root PATH] [--support-dir PATH]"

    let dryRun: Bool
    let transcriptsRoot: URL
    let supportDirectory: URL

    static func parse(arguments: [String], environment: [String: String]) -> DaemonOptions {
        var dryRun = environment["CC_VIGIL_DRY_RUN"] == "1"
        var transcriptsRoot = environment["CC_VIGIL_TRANSCRIPTS_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? SupportPaths.defaultTranscriptsRoot
        var supportDirectory = environment["CC_VIGIL_SUPPORT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? SupportPaths.defaultDirectory
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--dry-run":
                dryRun = true
            case "--transcripts-root":
                transcriptsRoot = URL(fileURLWithPath: requireValue(&iterator, for: argument), isDirectory: true)
            case "--support-dir":
                supportDirectory = URL(fileURLWithPath: requireValue(&iterator, for: argument), isDirectory: true)
            default:
                usageExit("unknown argument: \(argument)")
            }
        }
        return DaemonOptions(
            dryRun: dryRun,
            transcriptsRoot: transcriptsRoot,
            supportDirectory: supportDirectory
        )
    }

    private static func requireValue(
        _ iterator: inout IndexingIterator<[String]>,
        for argument: String
    ) -> String {
        guard let value = iterator.next() else {
            usageExit("\(argument) requires a path")
        }
        return value
    }

    private static func usageExit(_ message: String) -> Never {
        FileHandle.standardError.write(Data("CCVigilDaemon: \(message)\n\(usage)\n".utf8))
        exit(2)
    }
}
