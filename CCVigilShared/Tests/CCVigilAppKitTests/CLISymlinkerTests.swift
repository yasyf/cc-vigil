import CCVigilAppKit
import Foundation
import Testing

private struct FakeFSError: Error, CustomStringConvertible {
    let description: String
}

private final class FakeSymlinkFileSystem: SymlinkFileSystem, @unchecked Sendable {
    var existing: Set<String>
    var symlinks: [String: String]
    var resolvedPaths: [String: String] = [:]
    var undeletable: Set<String> = []
    var unwritableDirectories: Set<String> = []
    var uncreatableDirectories: Set<String> = []
    private(set) var log: [String] = []

    init(existing: Set<String> = [], symlinks: [String: String] = [:]) {
        self.existing = existing.union(symlinks.keys)
        self.symlinks = symlinks
    }

    func itemExists(atPath path: String) -> Bool {
        existing.contains(path)
    }

    func symlinkDestination(atPath path: String) -> String? {
        symlinks[path]
    }

    func resolvedPath(_ path: String) -> String {
        resolvedPaths[path] ?? path
    }

    func createDirectory(atPath path: String) throws {
        guard !uncreatableDirectories.contains(path) else {
            throw FakeFSError(description: "mkdir denied")
        }
        existing.insert(path)
        log.append("mkdir \(path)")
    }

    func removeItem(atPath path: String) throws {
        guard !undeletable.contains(path) else {
            throw FakeFSError(description: "rm denied")
        }
        existing.remove(path)
        symlinks.removeValue(forKey: path)
        log.append("rm \(path)")
    }

    func createSymbolicLink(atPath path: String, withDestinationPath destination: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        guard !unwritableDirectories.contains(directory) else {
            throw FakeFSError(description: "link denied")
        }
        existing.insert(path)
        symlinks[path] = destination
        log.append("ln \(path) -> \(destination)")
    }
}

private let cliPath = "/Applications/CCVigil.app/Contents/Helpers/cc-vigil"
private let directories = ["/usr/local/bin", "/Users/ada/.local/bin"]

@Test func linksIntoThePrimaryDirectory() {
    let fileSystem = FakeSymlinkFileSystem(existing: ["/usr/local/bin"])
    let outcome = CLISymlinker.link(cliPath: cliPath, directories: directories, fileSystem: fileSystem)
    #expect(outcome == .linked(path: "/usr/local/bin/cc-vigil"))
    #expect(fileSystem.symlinks["/usr/local/bin/cc-vigil"] == cliPath)
    #expect(fileSystem.log == ["ln /usr/local/bin/cc-vigil -> \(cliPath)"])
}

@Test func removesAStaleDestinationFirst() {
    let fileSystem = FakeSymlinkFileSystem(
        existing: ["/usr/local/bin"],
        symlinks: ["/usr/local/bin/cc-vigil": "/dead/old/cc-vigil"]
    )
    let outcome = CLISymlinker.link(cliPath: cliPath, directories: directories, fileSystem: fileSystem)
    #expect(outcome == .linked(path: "/usr/local/bin/cc-vigil"))
    #expect(fileSystem.log == [
        "rm /usr/local/bin/cc-vigil",
        "ln /usr/local/bin/cc-vigil -> \(cliPath)",
    ])
}

@Test func fallsBackWhenThePrimaryIsUnwritable() {
    let fileSystem = FakeSymlinkFileSystem(existing: ["/usr/local/bin"])
    fileSystem.unwritableDirectories = ["/usr/local/bin"]
    let outcome = CLISymlinker.link(cliPath: cliPath, directories: directories, fileSystem: fileSystem)
    #expect(outcome == .linked(path: "/Users/ada/.local/bin/cc-vigil"))
    #expect(fileSystem.log == [
        "mkdir /Users/ada/.local/bin",
        "ln /Users/ada/.local/bin/cc-vigil -> \(cliPath)",
    ])
}

@Test func fallsBackWhenTheStaleDestinationCannotBeRemoved() {
    let fileSystem = FakeSymlinkFileSystem(
        existing: ["/usr/local/bin", "/Users/ada/.local/bin"],
        symlinks: ["/usr/local/bin/cc-vigil": "/dead/old/cc-vigil"]
    )
    fileSystem.undeletable = ["/usr/local/bin/cc-vigil"]
    let outcome = CLISymlinker.link(cliPath: cliPath, directories: directories, fileSystem: fileSystem)
    #expect(outcome == .linked(path: "/Users/ada/.local/bin/cc-vigil"))
}

@Test func reportsAllFailuresWhenEveryDirectoryFails() {
    let fileSystem = FakeSymlinkFileSystem(existing: ["/usr/local/bin"])
    fileSystem.unwritableDirectories = ["/usr/local/bin"]
    fileSystem.uncreatableDirectories = ["/Users/ada/.local/bin"]
    let outcome = CLISymlinker.link(cliPath: cliPath, directories: directories, fileSystem: fileSystem)
    #expect(outcome == .failed(
        "/usr/local/bin/cc-vigil: link denied; /Users/ada/.local/bin/cc-vigil: mkdir denied"
    ))
}

@Test func defaultDirectoriesArePrimaryThenLocalBin() {
    let home = URL(fileURLWithPath: "/Users/ada")
    #expect(CLISymlinker.defaultDirectories(home: home) == [
        "/usr/local/bin",
        "/Users/ada/.local/bin",
    ])
}

@Test func removeLinksOnlyTouchesLinksIntoTheBundle() throws {
    let fileSystem = FakeSymlinkFileSystem(
        existing: ["/usr/local/bin", "/Users/ada/.local/bin"],
        symlinks: [
            "/usr/local/bin/cc-vigil": cliPath,
            "/Users/ada/.local/bin/cc-vigil": "/opt/homebrew/bin/cc-vigil",
        ]
    )
    let removed = try CLISymlinker.removeLinks(
        pointingInto: "/Applications/CCVigil.app",
        directories: directories,
        fileSystem: fileSystem
    )
    #expect(removed == ["/usr/local/bin/cc-vigil"])
    #expect(fileSystem.symlinks["/Users/ada/.local/bin/cc-vigil"] == "/opt/homebrew/bin/cc-vigil")
}

@Test func removeLinksResolvesTheBundlePathBeforeMatching() throws {
    // Install writes the link target through the resolved bundle path, so a bundle
    // under a symlinked directory has a resolved target that the raw bundle path
    // is not a prefix of. Uninstall must resolve the bundle path the same way.
    let resolvedCLIPath = "/Volumes/Data/Apps/CCVigil.app/Contents/Helpers/cc-vigil"
    let fileSystem = FakeSymlinkFileSystem(
        existing: ["/usr/local/bin"],
        symlinks: ["/usr/local/bin/cc-vigil": resolvedCLIPath]
    )
    fileSystem.resolvedPaths = ["/Users/ada/Apps/CCVigil.app": "/Volumes/Data/Apps/CCVigil.app"]
    let removed = try CLISymlinker.removeLinks(
        pointingInto: "/Users/ada/Apps/CCVigil.app",
        directories: directories,
        fileSystem: fileSystem
    )
    #expect(removed == ["/usr/local/bin/cc-vigil"])
    #expect(fileSystem.symlinks["/usr/local/bin/cc-vigil"] == nil)
}
