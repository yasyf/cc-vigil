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
            let input = try NudgeStdin.read(from: .standardInput)
            let payload = try HookInput.nudgePayload(
                fromHookJSON: input,
                claudePid: ClaudeAncestry.nearestClaudeAncestorOfSelf(),
                transcriptsRoot: Self.relocatedTranscriptsRoot(environment: ProcessInfo.processInfo.environment)
            )
            try socketOptions.client.send(.nudge(payload))
        } catch {
            let warning = "cc-vigil: nudge failed: \(String(describing: error))\n"
            FileHandle.standardError.write(Data(warning.utf8))
        }
    }

    /// A launchd daemon does not inherit the session's `CLAUDE_CONFIG_DIR`, but
    /// this hook runs inside it: forward the relocated transcripts root so the
    /// daemon can discover and scan it.
    public static func relocatedTranscriptsRoot(environment: [String: String]) -> String? {
        guard let dir = environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: dir, isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .path
    }
}
