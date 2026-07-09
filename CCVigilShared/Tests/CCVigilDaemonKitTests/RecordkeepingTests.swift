import CCVigilDaemonKit
import CCVigilShared
import Foundation
import Testing

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cc-vigil-records-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let at = Date(timeIntervalSince1970: 1_767_323_047)

@Test func eventLogAppendsJSONLines() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("events.log")
    let log = EventLog(url: url)
    try log.append(EventRecord(at: at, event: .wake))
    try log.append(EventRecord(at: at, event: .resumed))
    let contents = try String(contentsOf: url, encoding: .utf8)
    #expect(contents == "{\"at\":1767323047,\"event\":\"wake\"}\n{\"at\":1767323047,\"event\":\"resumed\"}\n")
}

@Test func eventLogRotatesOnceAtSizeLimit() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("events.log")
    let rotated = directory.appendingPathComponent("events.log.1")
    let lineBytes = 36
    let log = EventLog(url: url, maxBytes: lineBytes * 2)
    try log.append(EventRecord(at: at, event: .wake))
    try log.append(EventRecord(at: at, event: .wake))
    #expect(!FileManager.default.fileExists(atPath: rotated.path))
    try log.append(EventRecord(at: at, event: .resumed))
    let rotatedContents = try String(contentsOf: rotated, encoding: .utf8)
    #expect(rotatedContents == "{\"at\":1767323047,\"event\":\"wake\"}\n{\"at\":1767323047,\"event\":\"wake\"}\n")
    let liveContents = try String(contentsOf: url, encoding: .utf8)
    #expect(liveContents == "{\"at\":1767323047,\"event\":\"resumed\"}\n")
    // A second rotation replaces the previous .1 (single-rotation policy).
    try log.append(EventRecord(at: at, event: .wake))
    try log.append(EventRecord(at: at, event: .wake))
    #expect(try String(contentsOf: rotated, encoding: .utf8)
        == "{\"at\":1767323047,\"event\":\"resumed\"}\n{\"at\":1767323047,\"event\":\"wake\"}\n")
    #expect(try String(contentsOf: url, encoding: .utf8) == "{\"at\":1767323047,\"event\":\"wake\"}\n")
}

@Test func stateStoreRoundTripsAtomically() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json")
    #expect(try StateStore.load(url: url) == nil)
    let state = PersistedState(
        holds: [Hold(key: "ci", reason: "build", ttlSeconds: 600, createdAt: at, pid: 7)],
        pausedUntil: at
    )
    try StateStore.save(state, to: url)
    #expect(try StateStore.load(url: url) == state)
    try StateStore.save(PersistedState(holds: [], pausedUntil: nil), to: url)
    #expect(try StateStore.load(url: url) == PersistedState(holds: [], pausedUntil: nil))
}

@Test func stateStoreQuarantinesCorruptFile() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json")
    let corruptBytes = Data("{ this is not valid state ".utf8)
    try corruptBytes.write(to: url)

    #expect(try StateStore.load(url: url) == PersistedState(holds: [], pausedUntil: nil))
    #expect(!FileManager.default.fileExists(atPath: url.path))

    let quarantine = url.appendingPathExtension("corrupt")
    #expect(try Data(contentsOf: quarantine) == corruptBytes)

    let state = PersistedState(
        holds: [Hold(key: "ci", reason: "build", ttlSeconds: 600, createdAt: at, pid: 7)],
        pausedUntil: at
    )
    try StateStore.save(state, to: url)
    #expect(try StateStore.load(url: url) == state)
}

@Test func stateStoreQuarantineOverwritesPriorCorrupt() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json")
    let quarantine = url.appendingPathExtension("corrupt")
    try Data("stale corrupt bytes".utf8).write(to: quarantine)
    let corruptBytes = Data("fresh corrupt bytes {".utf8)
    try corruptBytes.write(to: url)

    #expect(try StateStore.load(url: url) == PersistedState(holds: [], pausedUntil: nil))
    #expect(try Data(contentsOf: quarantine) == corruptBytes)
}

@Test func configLoaderDefaultsWhenAbsent() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(try ConfigLoader.load(url: directory.appendingPathComponent("config.json")) == .default)
}

@Test func configLoaderReadsOverrides() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.json")
    try Data("{\"batteryFloorPercent\":30,\"pollBlockingSeconds\":5}".utf8).write(to: url)
    let config = try ConfigLoader.load(url: url)
    #expect(config.batteryFloorPercent == 30)
    #expect(config.pollBlockingSeconds == 5)
    #expect(config.thermalCutoutCelsius == 80)
}

@Test(arguments: [
    "not json at all",
    "{\"batteryFloorPercent\":99}",
    "{\"pollIdleSeconds\":0}",
])
func configLoaderQuarantinesInvalidConfig(contents: String) throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.json")
    let corruptBytes = Data(contents.utf8)
    try corruptBytes.write(to: url)

    #expect(try ConfigLoader.load(url: url) == .default)
    #expect(!FileManager.default.fileExists(atPath: url.path))

    let quarantine = url.appendingPathExtension("corrupt")
    #expect(try Data(contentsOf: quarantine) == corruptBytes)
}

@Test func configLoaderSaveRoundTripsNonDefaults() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.json")
    let config = try VigilConfig(
        batteryFloorPercent: 35,
        thermalCutoutCelsius: 90,
        activityWindowSeconds: 600,
        hideMenuBarExtra: true
    )
    try ConfigLoader.save(config, to: url)
    #expect(try ConfigLoader.load(url: url) == config)
    let contents = try String(contentsOf: url, encoding: .utf8)
    #expect(contents.contains("\"batteryFloorPercent\" : 35"))
    #expect(contents.contains("\"hideMenuBarExtra\" : true"))
}
