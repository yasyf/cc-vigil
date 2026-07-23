import CCVigilRuntime
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
    let prefix = "{\"payload\":{\"at\":1767323047,\"event\":"
    let suffix = "},\"schema\":\"dev.yasyf.cc-vigil.event\",\"schemaFingerprint\":\""
        + PersistedSchemaV1.eventFingerprint + "\",\"schemaVersion\":1}\n"
    #expect(contents == prefix + "\"wake\"" + suffix + prefix + "\"resumed\"" + suffix)
    #expect(try EventLog.decodeRecords(fromJSONL: Data(contents.utf8)) == [
        EventRecord(at: at, event: .wake),
        EventRecord(at: at, event: .resumed),
    ])
}

@Test func eventLogRotatesOnceAtSizeLimit() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("events.log")
    let rotated = directory.appendingPathComponent("events.log.1")
    let wakeLineBytes = try EventLog.encode(EventRecord(at: at, event: .wake)).count + 1
    let resumedLineBytes = try EventLog.encode(EventRecord(at: at, event: .resumed)).count + 1
    let log = EventLog(url: url, maxBytes: wakeLineBytes + resumedLineBytes)
    try log.append(EventRecord(at: at, event: .wake))
    try log.append(EventRecord(at: at, event: .wake))
    #expect(!FileManager.default.fileExists(atPath: rotated.path))
    try log.append(EventRecord(at: at, event: .resumed))
    let rotatedContents = try String(contentsOf: rotated, encoding: .utf8)
    #expect(try EventLog.decodeRecords(fromJSONL: Data(rotatedContents.utf8)) == [
        EventRecord(at: at, event: .wake),
        EventRecord(at: at, event: .wake),
    ])
    let liveContents = try String(contentsOf: url, encoding: .utf8)
    #expect(try EventLog.decodeRecords(fromJSONL: Data(liveContents.utf8)) == [
        EventRecord(at: at, event: .resumed),
    ])
    // A second rotation replaces the previous .1 (single-rotation policy).
    try log.append(EventRecord(at: at, event: .wake))
    try log.append(EventRecord(at: at, event: .wake))
    #expect(try EventLog.decodeRecords(fromJSONL: Data(contentsOf: rotated)) == [
        EventRecord(at: at, event: .resumed),
        EventRecord(at: at, event: .wake),
    ])
    #expect(try EventLog.decodeRecords(fromJSONL: Data(contentsOf: url)) == [
        EventRecord(at: at, event: .wake),
    ])
}

private func jsonObject(at url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func writeJSON(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
}

private func payload(in envelope: [String: Any]) throws -> [String: Any] {
    try #require(envelope["payload"] as? [String: Any])
}

@Test func persistedSchemaV1FingerprintsArePinned() {
    #expect(PersistedSchemaV1.configFingerprint
        == "dev.yasyf.cc-vigil.config.17c0fff2e9b6604ea00c3e404570aa1e5ccb240039891f4b83cd27940b947709")
    #expect(PersistedSchemaV1.stateFingerprint
        == "dev.yasyf.cc-vigil.state.b766bd33ef7db8fb7e18131aa0b4674e6df20863929728c38ef3e84a913915e3")
    #expect(PersistedSchemaV1.eventFingerprint
        == "dev.yasyf.cc-vigil.event.37caef1bfd1e1919e3b8481d20f7fbad6b4c490efbeff9b1ce94c5a50678c424")
}

@Test func eventLogRejectsEveryNonExactRecord() throws {
    let valid = try String(
        decoding: EventLog.encode(EventRecord(at: at, event: .wake)),
        as: UTF8.self
    )
    let brokenRecords = [
        "{\"at\":1767323047,\"event\":\"wake\"}",
        valid.replacingOccurrences(of: PersistedSchemaV1.eventIdentity, with: "dev.yasyf.foreign"),
        valid.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
        valid.replacingOccurrences(
            of: PersistedSchemaV1.eventFingerprint,
            with: PersistedSchemaV1.eventIdentity + ".stale"
        ),
        valid.replacingOccurrences(of: "\"at\":1767323047,", with: ""),
        valid.replacingOccurrences(of: "\"event\":\"wake\"", with: "\"event\":\"wake\",\"extra\":true"),
        valid.replacingOccurrences(of: "\"event\":\"wake\"", with: "\"event\":\"wake\",\"event\":\"wake\""),
        valid.replacingOccurrences(of: "\"event\":\"wake\"", with: "\"event\":\"newer-event\""),
        String(valid.dropLast()) + ",\"legacy\":true}",
        valid + " {}",
        "{",
    ]
    for broken in brokenRecords {
        #expect(throws: (any Error).self) {
            try EventLog.decodeRecords(fromJSONL: Data((broken + "\n").utf8))
        }
    }
    #expect(throws: (any Error).self) {
        try EventLog.decodeRecords(fromJSONL: Data((valid + "\n\n" + valid + "\n").utf8))
    }
}

@Test func stateStoreRoundTripsExactV1Envelope() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json")
    #expect(try StateStore.load(url: url) == nil)
    let state = PersistedState(
        holds: [Hold(key: "ci", reason: "build", ttlSeconds: 600, createdAt: at, pid: 7)],
        pausedUntil: at,
        registeredRoots: ["/relocated/.claude/projects"]
    )
    try StateStore.save(state, to: url)
    #expect(try StateStore.load(url: url) == state)

    let envelope = try jsonObject(at: url)
    #expect(Set(envelope.keys) == ["payload", "schema", "schemaFingerprint", "schemaVersion"])
    #expect(envelope["schema"] as? String == PersistedSchemaV1.stateIdentity)
    #expect(envelope["schemaVersion"] as? Int == PersistedSchemaV1.version)
    #expect(envelope["schemaFingerprint"] as? String == PersistedSchemaV1.stateFingerprint)
    #expect(try Set(payload(in: envelope).keys) == [
        "alertedCutouts", "holds", "nextAlertId", "pausedUntil", "recentAlerts", "registeredRoots",
    ])
}

@Test(arguments: [
    "not json at all",
    "{\"holds\":[],\"pausedUntil\":1767323100}",
])
func stateStoreRejectsInvalidAndOldShapes(contents: String) throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json")
    let bytes = Data(contents.utf8)
    try bytes.write(to: url)

    #expect(throws: (any Error).self) {
        try StateStore.load(url: url)
    }
    #expect(try Data(contentsOf: url) == bytes)
    #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
}

@Test func stateStoreRejectsIdentityDrift() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json")
    let state = PersistedState(
        holds: [Hold(key: "ci", reason: "build", ttlSeconds: 600, createdAt: at, pid: 7)],
        pausedUntil: nil
    )
    try StateStore.save(state, to: url)
    let original = try jsonObject(at: url)

    for (field, value) in [
        ("schema", "dev.yasyf.cc-vigil.legacy" as Any),
        ("schemaVersion", 2 as Any),
        ("schemaFingerprint", "cc-vigil.state.stale" as Any),
    ] {
        var changed = original
        changed[field] = value
        try writeJSON(changed, to: url)
        #expect(throws: DecodingError.self) {
            try StateStore.load(url: url)
        }
    }

    var changed = original
    changed["legacyEnvelopeField"] = true
    try writeJSON(changed, to: url)
    #expect(throws: DecodingError.self) {
        try StateStore.load(url: url)
    }

    changed = original
    changed.removeValue(forKey: "schemaFingerprint")
    try writeJSON(changed, to: url)
    #expect(throws: DecodingError.self) {
        try StateStore.load(url: url)
    }
}

@Test func stateStoreRejectsPayloadShapeDrift() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json")
    let state = PersistedState(
        holds: [Hold(key: "ci", reason: "build", ttlSeconds: 600, createdAt: at, pid: 7)],
        pausedUntil: nil
    )
    try StateStore.save(state, to: url)
    let original = try jsonObject(at: url)

    var changed = original
    var changedPayload = try payload(in: original)
    changedPayload.removeValue(forKey: "registeredRoots")
    changed["payload"] = changedPayload
    try writeJSON(changed, to: url)
    #expect(throws: DecodingError.self) {
        try StateStore.load(url: url)
    }

    changed = original
    changedPayload = try payload(in: original)
    var holds = try #require(changedPayload["holds"] as? [[String: Any]])
    holds[0]["legacyField"] = true
    changedPayload["holds"] = holds
    changed["payload"] = changedPayload
    try writeJSON(changed, to: url)
    #expect(throws: DecodingError.self) {
        try StateStore.load(url: url)
    }
}

@Test func configLoaderDefaultsOnlyWhenAbsent() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(try ConfigLoader.load(url: directory.appendingPathComponent("config.json")) == .default)
}

@Test func configLoaderRoundTripsExactV1Envelope() throws {
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

    let envelope = try jsonObject(at: url)
    #expect(Set(envelope.keys) == ["payload", "schema", "schemaFingerprint", "schemaVersion"])
    #expect(envelope["schema"] as? String == PersistedSchemaV1.configIdentity)
    #expect(envelope["schemaVersion"] as? Int == PersistedSchemaV1.version)
    #expect(envelope["schemaFingerprint"] as? String == PersistedSchemaV1.configFingerprint)
    #expect(try Set(payload(in: envelope).keys) == [
        "activityWindowSeconds",
        "batteryFloorPercent",
        "hideMenuBarExtra",
        "lowPowerCutout",
        "notifyOnCutout",
        "notifyOnRelease",
        "pendingAsyncMaxAgeSeconds",
        "pollBlockingSeconds",
        "pollIdleSeconds",
        "thermalCutoutCelsius",
        "transcriptsRoots",
    ])
}

@Test(arguments: [
    "not json at all",
    "{\"batteryFloorPercent\":30,\"pollBlockingSeconds\":5}",
])
func configLoaderRejectsInvalidAndOldShapes(contents: String) throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.json")
    let bytes = Data(contents.utf8)
    try bytes.write(to: url)

    #expect(throws: (any Error).self) {
        try ConfigLoader.load(url: url)
    }
    #expect(try Data(contentsOf: url) == bytes)
    #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
}

@Test func configLoaderRejectsIdentityAndPayloadDrift() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.json")
    try ConfigLoader.save(.default, to: url)
    let original = try jsonObject(at: url)

    for (field, value) in [
        ("schema", "dev.yasyf.cc-vigil.legacy" as Any),
        ("schemaVersion", 2 as Any),
        ("schemaFingerprint", "cc-vigil.config.stale" as Any),
    ] {
        var changed = original
        changed[field] = value
        try writeJSON(changed, to: url)
        #expect(throws: DecodingError.self) {
            try ConfigLoader.load(url: url)
        }
    }

    var changed = original
    var changedPayload = try payload(in: original)
    changedPayload.removeValue(forKey: "lowPowerCutout")
    changed["payload"] = changedPayload
    try writeJSON(changed, to: url)
    #expect(throws: DecodingError.self) {
        try ConfigLoader.load(url: url)
    }

    changed = original
    changedPayload = try payload(in: original)
    changedPayload["legacyFallback"] = true
    changed["payload"] = changedPayload
    try writeJSON(changed, to: url)
    #expect(throws: DecodingError.self) {
        try ConfigLoader.load(url: url)
    }

    changed = original
    changedPayload = try payload(in: original)
    changedPayload["pollIdleSeconds"] = 0
    changed["payload"] = changedPayload
    try writeJSON(changed, to: url)
    #expect(throws: VigilConfigError.outOfRange(field: "pollIdleSeconds", allowed: "1-600")) {
        try ConfigLoader.load(url: url)
    }
}
