import CCVigilShared
import Foundation
import Testing

let fixtureLastEventEpoch: Int64 = 1_767_323_047

struct FixedClock: WallClock {
    let now: Date

    init(epoch: Int64) {
        now = Date(timeIntervalSince1970: TimeInterval(epoch))
    }
}

func fixtureURL(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
}

struct TranscriptsRoot {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-vigil-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func install(
        fixture: String,
        as name: String,
        in project: String = "project",
        mtimeEpoch: Int64 = fixtureLastEventEpoch
    ) throws -> URL {
        let projectDirectory = root.appendingPathComponent(project, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let destination = projectDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixtureURL(fixture), to: destination)
        try setMtime(destination, epoch: mtimeEpoch)
        return destination
    }

    func setMtime(_ url: URL, epoch: Int64) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(epoch))],
            ofItemAtPath: url.path
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
