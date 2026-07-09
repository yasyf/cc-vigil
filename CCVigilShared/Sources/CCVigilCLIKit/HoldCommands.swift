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

    public static func perform(
        key: String,
        reason: String,
        ttlSeconds: Int,
        send: (WireRequest) throws -> WireResponse,
        emit: (String) -> Void
    ) throws {
        emit("holding \(key) for \(Durations.text(forSeconds: ttlSeconds)); release with: cc-vigil release \(key)")
        try requireOK(send(.hold(key: key, reason: reason, ttlSeconds: ttlSeconds, pid: nil)))
    }

    public func run() throws {
        let ttlSeconds = try min(Durations.seconds(from: duration), Hold.maxTTLSeconds)
        let holdKey = key ?? "cli-\(UUID().uuidString.prefix(8).lowercased())"
        try Self.perform(
            key: holdKey,
            reason: reason,
            ttlSeconds: ttlSeconds,
            send: socketOptions.client.roundTrip,
            emit: { print($0) }
        )
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
