import ArgumentParser
import CCVigilShared

public struct PauseCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause all blocking for a fixed duration."
    )

    @Option(name: .customLong("for"), help: "Duration: seconds or <n>s|m|h|d")
    public var duration: String

    @OptionGroup public var socketOptions: SocketOptions

    public init() {}

    public func run() throws {
        let seconds = try Durations.seconds(from: duration)
        try requireOK(socketOptions.client.roundTrip(.pause(seconds: seconds)))
        print("paused for \(Durations.text(forSeconds: seconds))")
    }
}

public struct ResumeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume blocking after a pause."
    )

    @OptionGroup public var socketOptions: SocketOptions

    public init() {}

    public func run() throws {
        try requireOK(socketOptions.client.roundTrip(.pause(seconds: 0)))
        print("resumed")
    }
}
