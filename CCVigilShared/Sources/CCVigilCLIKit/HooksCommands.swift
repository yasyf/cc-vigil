import ArgumentParser

public struct InstallHooksCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install-hooks",
        abstract: "Install cc-vigil nudge hooks into Claude Code's settings.json."
    )

    @Option(help: "Path to Claude Code's settings.json")
    public var settings: String = defaultClaudeSettingsPath

    public init() {}

    public func run() throws {
        let command = try HookSettingsFile.install(
            settingsPath: settings,
            cliPath: ExecutablePath.resolved()
        )
        print("installed hooks running `\(command)` in \(settings)")
    }
}

public struct UninstallHooksCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "uninstall-hooks",
        abstract: "Remove cc-vigil hooks from Claude Code's settings.json."
    )

    @Option(help: "Path to Claude Code's settings.json")
    public var settings: String = defaultClaudeSettingsPath

    public init() {}

    public func run() throws {
        try HookSettingsFile.uninstall(settingsPath: settings)
        print("removed cc-vigil hooks from \(settings)")
    }
}
