import ArgumentParser
import CCVigilShared
import CCVigilTransport
import Foundation

public struct StatusCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show what the daemon is doing and why."
    )

    @Flag(help: "Print the raw status report JSON")
    public var json = false

    @OptionGroup public var socketOptions: SocketOptions

    public init() {}

    public func run() throws {
        let reply = try socketOptions.client.roundTrip(.status)
        guard case let .status(report) = reply else {
            if case let .error(message) = reply {
                throw CLIError.daemonError(message)
            }
            throw CLIError.unexpectedReply(reply)
        }
        if json {
            try print(StatusRenderer.renderJSON(report))
        } else {
            print(StatusRenderer.render(report, now: Date()))
        }
    }
}
