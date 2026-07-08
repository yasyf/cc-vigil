import ArgumentParser
import CCVigilCLIKit
import CCVigilDaemonKit
import Testing

@Test func parsesHold() throws {
    let parsed = try VigilCLI.parseAsRoot([
        "hold", "--for", "45m", "--reason", "bake", "--key", "k1", "--socket", "/tmp/x.sock",
    ])
    let hold = try #require(parsed as? HoldCommand)
    #expect(hold.duration == "45m")
    #expect(hold.reason == "bake")
    #expect(hold.key == "k1")
    #expect(hold.socketOptions.socket == "/tmp/x.sock")
}

@Test func holdKeyDefaultsToGenerated() throws {
    let parsed = try VigilCLI.parseAsRoot(["hold", "--for", "30s", "--reason", "r"])
    let hold = try #require(parsed as? HoldCommand)
    #expect(hold.key == nil)
}

@Test func holdRequiresDuration() {
    #expect(throws: (any Error).self) {
        try VigilCLI.parseAsRoot(["hold", "--reason", "r"])
    }
}

@Test func parsesStatusWithDefaults() throws {
    let parsed = try VigilCLI.parseAsRoot(["status"])
    let status = try #require(parsed as? StatusCommand)
    #expect(status.json == false)
    #expect(status.socketOptions.socket == SupportPaths(directory: SupportPaths.defaultDirectory).socketPath)
}

@Test func parsesStatusJSONFlag() throws {
    let parsed = try VigilCLI.parseAsRoot(["status", "--json"])
    let status = try #require(parsed as? StatusCommand)
    #expect(status.json == true)
}

@Test func parsesRelease() throws {
    let parsed = try VigilCLI.parseAsRoot(["release", "k1"])
    let release = try #require(parsed as? ReleaseCommand)
    #expect(release.key == "k1")
}

@Test func parsesPauseAndResume() throws {
    let pause = try #require(try VigilCLI.parseAsRoot(["pause", "--for", "10m"]) as? PauseCommand)
    #expect(pause.duration == "10m")
    #expect(try VigilCLI.parseAsRoot(["resume"]) is ResumeCommand)
}

@Test func parsesLogFlags() throws {
    let parsed = try VigilCLI.parseAsRoot(["log", "-f", "-n", "5", "--support-dir", "/tmp/sd"])
    let log = try #require(parsed as? LogCommand)
    #expect(log.follow == true)
    #expect(log.lines == 5)
    #expect(log.supportDir == "/tmp/sd")
}

@Test func logDefaultsToTenLinesNoFollow() throws {
    let parsed = try VigilCLI.parseAsRoot(["log"])
    let log = try #require(parsed as? LogCommand)
    #expect(log.follow == false)
    #expect(log.lines == 10)
    #expect(log.supportDir == SupportPaths.defaultDirectory.path)
}

@Test func parsesHookCommands() throws {
    let install = try #require(
        try VigilCLI.parseAsRoot(["install-hooks", "--settings", "/tmp/s.json"]) as? InstallHooksCommand
    )
    #expect(install.settings == "/tmp/s.json")
    let uninstall = try #require(
        try VigilCLI.parseAsRoot(["uninstall-hooks", "--settings", "/tmp/s.json"]) as? UninstallHooksCommand
    )
    #expect(uninstall.settings == "/tmp/s.json")
}

@Test func parsesNudgeAndVersion() throws {
    #expect(try VigilCLI.parseAsRoot(["nudge"]) is NudgeCommand)
    #expect(try VigilCLI.parseAsRoot(["version"]) is VersionCommand)
}

@Test func rejectsUnknownSubcommands() {
    #expect(throws: (any Error).self) {
        try VigilCLI.parseAsRoot(["explode"])
    }
}
