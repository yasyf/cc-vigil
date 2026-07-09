import Foundation

public protocol SymlinkFileSystem: Sendable {
    /// True when a filesystem entry exists at the path, including a dangling symlink.
    func itemExists(atPath path: String) -> Bool
    func symlinkDestination(atPath path: String) -> String?
    /// Resolves symlinks in the path the same way install writes link targets.
    func resolvedPath(_ path: String) -> String
    func createDirectory(atPath path: String) throws
    func removeItem(atPath path: String) throws
    func createSymbolicLink(atPath path: String, withDestinationPath destination: String) throws
}

public struct SystemSymlinkFileSystem: SymlinkFileSystem {
    public init() {}

    public func itemExists(atPath path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)) != nil
    }

    public func symlinkDestination(atPath path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    public func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    public func createDirectory(atPath path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public func removeItem(atPath path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    public func createSymbolicLink(atPath path: String, withDestinationPath destination: String) throws {
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destination)
    }
}

public enum CLISymlinker {
    public static let binaryName = "cc-vigil"

    public static func defaultDirectories(home: URL) -> [String] {
        ["/usr/local/bin", home.appendingPathComponent(".local/bin").path]
    }

    public static func link(
        cliPath: String,
        directories: [String],
        fileSystem: some SymlinkFileSystem
    ) -> SymlinkOutcome {
        var failures: [String] = []
        for directory in directories {
            let destination = "\(directory)/\(binaryName)"
            do {
                if !fileSystem.itemExists(atPath: directory) {
                    try fileSystem.createDirectory(atPath: directory)
                }
                if fileSystem.itemExists(atPath: destination) {
                    try fileSystem.removeItem(atPath: destination)
                }
                try fileSystem.createSymbolicLink(atPath: destination, withDestinationPath: cliPath)
                return .linked(path: destination)
            } catch {
                failures.append("\(destination): \(error)")
            }
        }
        return .failed(failures.joined(separator: "; "))
    }

    public static func removeLinks(
        pointingInto bundlePath: String,
        directories: [String],
        fileSystem: some SymlinkFileSystem
    ) throws -> [String] {
        let resolvedBundlePath = fileSystem.resolvedPath(bundlePath)
        var removed: [String] = []
        for directory in directories {
            let destination = "\(directory)/\(binaryName)"
            guard let target = fileSystem.symlinkDestination(atPath: destination),
                  target.hasPrefix(resolvedBundlePath)
            else { continue }
            try fileSystem.removeItem(atPath: destination)
            removed.append(destination)
        }
        return removed
    }
}
