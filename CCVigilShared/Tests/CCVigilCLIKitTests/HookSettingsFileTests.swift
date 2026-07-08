import CCVigilCLIKit
import CCVigilShared
import Foundation
import Testing

private let cliPath = "/Applications/CCVigil.app/Contents/Helpers/cc-vigil"

@Test func installsIntoMissingFile() throws {
    let dir = try ShortTempDir(prefix: "hooks")
    defer { dir.tearDown() }
    let settings = dir.path("settings.json")

    let command = try HookSettingsFile.install(settingsPath: settings, cliPath: cliPath)

    #expect(command == "\(cliPath) nudge")
    #expect(try HookSettingsFile.state(settingsPath: settings, cliPath: cliPath) == .installed)
    let text = try String(contentsOfFile: settings, encoding: .utf8)
    #expect(text.contains("\(cliPath) nudge"))
    #expect(text.contains("\"_cc_vigil\""))
}

@Test func installPreservesUserContent() throws {
    let dir = try ShortTempDir(prefix: "hooks")
    defer { dir.tearDown() }
    let settings = dir.path("settings.json")
    let seed = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}"#
    try Data(seed.utf8).write(to: URL(fileURLWithPath: settings))

    try HookSettingsFile.install(settingsPath: settings, cliPath: cliPath)

    let root = try #require(
        try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: settings)))
            as? [String: Any]
    )
    #expect(root["model"] as? String == "opus")
    let text = try String(contentsOfFile: settings, encoding: .utf8)
    #expect(text.contains("echo hi"))
    #expect(try HookSettingsFile.state(settingsPath: settings, cliPath: cliPath) == .installed)
}

@Test func uninstallRemovesOnlyTaggedHandlers() throws {
    let dir = try ShortTempDir(prefix: "hooks")
    defer { dir.tearDown() }
    let settings = dir.path("settings.json")
    let seed = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}"#
    try Data(seed.utf8).write(to: URL(fileURLWithPath: settings))
    try HookSettingsFile.install(settingsPath: settings, cliPath: cliPath)

    try HookSettingsFile.uninstall(settingsPath: settings)

    let text = try String(contentsOfFile: settings, encoding: .utf8)
    #expect(!text.contains("_cc_vigil"))
    #expect(text.contains("echo hi"))
    #expect(try HookSettingsFile.state(settingsPath: settings, cliPath: cliPath) == .notInstalled)
}

@Test func uninstallWithoutSettingsThrows() throws {
    let dir = try ShortTempDir(prefix: "hooks")
    defer { dir.tearDown() }
    let settings = dir.path("settings.json")
    #expect(throws: HookSettingsFileError.missingSettings(settings)) {
        try HookSettingsFile.uninstall(settingsPath: settings)
    }
}

@Test func missingFileReportsNotInstalled() throws {
    let dir = try ShortTempDir(prefix: "hooks")
    defer { dir.tearDown() }
    #expect(try HookSettingsFile.state(settingsPath: dir.path("nope.json"), cliPath: cliPath) == .notInstalled)
}
