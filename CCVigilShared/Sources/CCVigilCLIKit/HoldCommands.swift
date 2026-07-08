import ArgumentParser
import CCVigilShared
import Foundation

public struct HoldCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "hold",
        abstract: "Hold the system awake for a fixed duration, no oracle required."
    )

    @Option(name: .customLong("for"), help: "Duration: seconds or <n>s|m|h|d (clamped to 24h)")
    public var duration: String

    @Option(help: "Why the hold exists")
    public var reason: String

    @Option(help: "Hold key (defaults to a generated cli-<id>)")
    public var key: String?

    @OptionGroup public var socketOptions: SocketOptions

    public init() {}

    public func run() throws {
        let ttlSeconds = try min(Durations.seconds(from: duration), Hold.maxTTLSeconds)
        let holdKey = key ?? "cli-\(UUID().uuidString.prefix(8).lowercased())"
        try requireOK(socketOptions.client.roundTrip(
            .hold(key: holdKey, reason: reason, ttlSeconds: ttlSeconds, pid: nil)
        ))
        let ttlText = Durations.text(forSeconds: ttlSeconds)
        print("holding \(holdKey) for \(ttlText); release with: cc-vigil release \(holdKey)")
    }
}

public struct ReleaseCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Release a hold."
    )

    @Argument(help: "The hold key")
    public var key: String

    @OptionGroup public var socketOptions: SocketOptions

    public init() {}

    public func run() throws {
        try requireOK(socketOptions.client.roundTrip(.release(key: key)))
        print("released \(key)")
    }
}
