import CCVigilShared
import Foundation

public enum HookSettingsFileError: Error, Equatable, CustomStringConvertible {
    case missingSettings(String)

    public var description: String {
        switch self {
        case let .missingSettings(path): "no settings file at \(path)"
        }
    }
}

public enum HookSettingsFile {
    @discardableResult
    public static func install(settingsPath: String, cliPath: String) throws -> String {
        let url = URL(fileURLWithPath: settingsPath)
        let updated = try HookInstaller.install(into: read(url), cliPath: cliPath)
        try write(updated, to: url)
        return HookInstaller.command(cliPath: cliPath)
    }

    public static func uninstall(settingsPath: String) throws {
        let url = URL(fileURLWithPath: settingsPath)
        guard let existing = try read(url) else {
            throw HookSettingsFileError.missingSettings(settingsPath)
        }
        let updated = try HookInstaller.remove(from: existing)
        try write(updated, to: url)
    }

    public static func state(settingsPath: String, cliPath: String) throws -> HookInstallState {
        try HookInstaller.state(of: read(URL(fileURLWithPath: settingsPath)), cliPath: cliPath)
    }

    private static func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }
}
