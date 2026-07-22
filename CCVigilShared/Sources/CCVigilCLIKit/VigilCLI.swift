import ArgumentParser
import CCVigilRuntime
import CCVigilShared
import CCVigilTransport
import Foundation

public struct VigilCLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "cc-vigil",
        abstract: "Keep the Mac awake while Claude Code agents are truly working.",
        subcommands: [
            NudgeCommand.self,
            StatusCommand.self,
            HoldCommand.self,
            ReleaseCommand.self,
            PauseCommand.self,
            ResumeCommand.self,
            LogCommand.self,
            InstallHooksCommand.self,
            UninstallHooksCommand.self,
            VersionCommand.self,
        ]
    )

    public init() {}
}

public struct SocketOptions: ParsableArguments {
    @Option(help: "Path to the daemon's cli.sock")
    public var socket: String = SupportPaths(directory: SupportPaths.defaultDirectory).socketPath

    public init() {}

    public var client: CLIDaemonClient {
        CLIDaemonClient(path: socket)
    }
}

enum CLIError: Error, CustomStringConvertible {
    case daemonError(String)
    case unexpectedReply(WireResponse)
    case missingEventsLog(String)
    case versionUnavailable

    var description: String {
        switch self {
        case let .daemonError(message):
            "daemon: \(message)"
        case let .unexpectedReply(reply):
            "unexpected reply from the daemon: \(reply)"
        case let .missingEventsLog(path):
            "no events log at \(path); has the daemon started?"
        case .versionUnavailable:
            "no CFBundleShortVersionString in the embedded Info.plist"
        }
    }
}

func requireOK(_ reply: WireResponse) throws {
    switch reply {
    case .ok:
        return
    case let .error(message):
        throw CLIError.daemonError(message)
    case .status:
        throw CLIError.unexpectedReply(reply)
    }
}

let defaultClaudeSettingsPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/settings.json").path
