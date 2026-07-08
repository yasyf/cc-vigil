import ArgumentParser
import Foundation

public struct VersionCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the cc-vigil version."
    )

    public init() {}

    public func run() throws {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            throw CLIError.versionUnavailable
        }
        print("cc-vigil \(version)")
    }
}
