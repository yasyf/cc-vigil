import Foundation

public struct SupportPaths: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/cc-vigil", isDirectory: true)
    }

    public static var defaultTranscriptsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    public var configURL: URL {
        directory.appendingPathComponent("config.json")
    }

    public var stateURL: URL {
        directory.appendingPathComponent("state.json")
    }

    public var eventsURL: URL {
        directory.appendingPathComponent("events.log")
    }

    public var socketPath: String {
        directory.appendingPathComponent("cli.sock").path
    }

    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
