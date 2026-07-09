import ArgumentParser
import CCVigilShared
import Foundation

public struct NudgeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "nudge",
        abstract: "Forward a Claude Code hook event to the daemon (always exits 0)."
    )

    @OptionGroup public var socketOptions: SocketOptions

    public init() {}

    /// The hook path must never break a Claude Code session: any failure is
    /// one stderr warning and a clean exit 0.
    public func run() {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let payload = try HookInput.nudgePayload(
                fromHookJSON: input,
                claudePid: ClaudeAncestry.nearestClaudeAncestorOfSelf()
            )
            try socketOptions.client.send(.nudge(payload))
        } catch {
            let warning = "cc-vigil: nudge failed: \(String(describing: error))\n"
            FileHandle.standardError.write(Data(warning.utf8))
        }
    }
}
