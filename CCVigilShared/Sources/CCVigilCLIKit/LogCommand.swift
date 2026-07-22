import ArgumentParser
import CCVigilRuntime
import Darwin
import Foundation

public struct LogCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Tail the daemon's events.log."
    )

    static let followPollMicroseconds: UInt32 = 500_000

    @Flag(name: [.customShort("f"), .customLong("follow")], help: "Keep printing appended events")
    public var follow = false

    @Option(name: [.customShort("n"), .customLong("lines")], help: "How many trailing lines to print")
    public var lines = LogTail.defaultLineCount

    @Option(name: .customLong("support-dir"), help: "cc-vigil support directory")
    public var supportDir: String = SupportPaths.defaultDirectory.path

    public init() {}

    public func validate() throws {
        guard lines >= 0 else {
            throw ValidationError("--lines must be zero or greater, got \(lines)")
        }
    }

    public func run() throws {
        let url = SupportPaths(directory: URL(fileURLWithPath: supportDir, isDirectory: true)).eventsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.missingEventsLog(url.path)
        }
        let existing = try Data(contentsOf: url)
        guard let text = String(data: existing, encoding: .utf8) else {
            throw CLIError.missingEventsLog(url.path)
        }
        for line in LogTail.lastLines(of: text, count: lines) {
            print(line)
        }
        guard follow else { return }
        var offset = UInt64(existing.count)
        while true {
            usleep(Self.followPollMicroseconds)
            offset = printAppended(at: url, from: offset)
        }
    }

    /// A shrink means the log rotated out from under us: restart from zero.
    private func printAppended(at url: URL, from previousOffset: UInt64) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sizeNumber = attributes[.size] as? NSNumber
        else { return previousOffset }
        let size = sizeNumber.uint64Value
        let offset = size < previousOffset ? 0 : previousOffset
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else {
            return offset
        }
        FileHandle.standardOutput.write(data)
        return offset + UInt64(data.count)
    }
}
