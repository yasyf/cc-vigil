import CCVigilAppKit
import CCVigilShared
import Foundation
import Testing

private func isolatedDefaults() -> UserDefaults {
    let name = "dev.yasyf.cc-vigil.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func appStateFingerprintIsPinned() {
    #expect(AppStateSchemaV1.fingerprint
        == "dev.yasyf.cc-vigil.app-state.8e9d2f79077fe68567a91b8c1e8e5305853fc8921d05a9619c21c500655b25d7")
}

@Test func appStateUsesOneExactNamespacedV1Envelope() throws {
    let defaults = isolatedDefaults()
    let store = try UserDefaultsAppStateStore(defaults: defaults)
    #expect(store.firstRunCompleted == false)
    #expect(store.lastMenuOpenedAt == nil)
    #expect(store.consecutiveFailures == 0)
    #expect(store.lastSeenAlertId == nil)

    let opened = Date(timeIntervalSince1970: 1_767_323_047)
    store.recordFirstRunCompleted(true)
    store.recordMenuOpened(at: opened)
    store.record(2)
    store.recordSeen(42)

    let data = try #require(defaults.data(forKey: AppStateSchemaV1.storageKey))
    let exact = "{\"payload\":{\"firstRunCompleted\":true,\"lastMenuOpenedAt\":1767323047,"
        + "\"lastSeenSleepAlertId\":42,\"repairConsecutiveFailures\":2},"
        + "\"schema\":\"\(AppStateSchemaV1.identity)\","
        + "\"schemaFingerprint\":\"\(AppStateSchemaV1.fingerprint)\",\"schemaVersion\":1}"
    #expect(String(decoding: data, as: UTF8.self) == exact)

    let reloaded = try UserDefaultsAppStateStore(defaults: defaults)
    #expect(reloaded.firstRunCompleted)
    #expect(reloaded.lastMenuOpenedAt == opened)
    #expect(reloaded.consecutiveFailures == 2)
    #expect(reloaded.lastSeenAlertId == 42)
    #expect(defaults.object(forKey: "firstRunCompleted") == nil)
    #expect(defaults.object(forKey: "lastMenuOpenedAt") == nil)
    #expect(defaults.object(forKey: "repairConsecutiveFailures") == nil)
    #expect(defaults.object(forKey: "lastSeenSleepAlertId") == nil)
}

@Test func appStateRejectsInvalidTypeAndEveryNonExactEnvelope() throws {
    let defaults = isolatedDefaults()
    defaults.set("42", forKey: AppStateSchemaV1.storageKey)
    #expect(throws: (any Error).self) {
        try UserDefaultsAppStateStore(defaults: defaults)
    }

    defaults.removeObject(forKey: AppStateSchemaV1.storageKey)
    let store = try UserDefaultsAppStateStore(defaults: defaults)
    store.recordSeen(7)
    let valid = try String(
        decoding: #require(defaults.data(forKey: AppStateSchemaV1.storageKey)),
        as: UTF8.self
    )
    let brokenValues = [
        "{\"firstRunCompleted\":false}",
        valid.replacingOccurrences(of: AppStateSchemaV1.identity, with: "dev.yasyf.foreign"),
        valid.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
        valid.replacingOccurrences(
            of: AppStateSchemaV1.fingerprint,
            with: AppStateSchemaV1.identity + ".stale"
        ),
        valid.replacingOccurrences(of: "\"firstRunCompleted\":false,", with: ""),
        valid.replacingOccurrences(
            of: "\"repairConsecutiveFailures\":0",
            with: "\"repairConsecutiveFailures\":0,\"legacy\":true"
        ),
        valid.replacingOccurrences(
            of: "\"repairConsecutiveFailures\":0",
            with: "\"repairConsecutiveFailures\":0,\"repairConsecutiveFailures\":0"
        ),
        valid.replacingOccurrences(of: "\"firstRunCompleted\":false", with: "\"firstRunCompleted\":null"),
        valid.replacingOccurrences(of: "\"lastSeenSleepAlertId\":7", with: "\"lastSeenSleepAlertId\":0"),
        valid.replacingOccurrences(of: "\"repairConsecutiveFailures\":0", with: "\"repairConsecutiveFailures\":-1"),
        String(valid.dropLast()) + ",\"legacy\":true}",
        valid + " {}",
        "{",
    ]
    for broken in brokenValues {
        defaults.set(Data(broken.utf8), forKey: AppStateSchemaV1.storageKey)
        #expect(throws: (any Error).self) {
            try UserDefaultsAppStateStore(defaults: defaults)
        }
    }
}

@Test func alertWatermarkSurvivesRestartAndSuppressesReplaysExactlyOnce() throws {
    let defaults = isolatedDefaults()
    let firstStore = try UserDefaultsAppStateStore(defaults: defaults)
    let firstNotifier = SleepNotifier(store: firstStore)
    let baseline = SleepAlert(id: 1, atEpoch: 100, payload: .released(sessions: 1, holds: 0))
    let second = SleepAlert(id: 2, atEpoch: 101, payload: .released(sessions: 1, holds: 0))
    let report: ([SleepAlert]?) -> StatusViewModel.Event = { alerts in
        .statusUpdated(StatusReport(
            shouldBlock: false,
            blockApplied: false,
            helper: .reachable,
            activeSessions: [],
            holds: [],
            latchedCutouts: [],
            pausedUntil: nil,
            alerts: alerts
        ))
    }
    firstNotifier.consume(
        report([baseline]),
        settings: NotificationSettings(notifyOnRelease: true, notifyOnCutout: true),
        post: { _ in Issue.record("baseline must not replay") }
    )
    #expect(firstStore.lastSeenAlertId == 1)

    let restartedStore = try UserDefaultsAppStateStore(defaults: defaults)
    var delivered: [SleepNotification.Kind] = []
    SleepNotifier(store: restartedStore).consume(
        report([baseline, second]),
        settings: NotificationSettings(notifyOnRelease: true, notifyOnCutout: true),
        post: { delivered.append($0.kind) }
    )
    #expect(delivered == [.released])
    #expect(restartedStore.lastSeenAlertId == 2)

    let restartedAgain = try UserDefaultsAppStateStore(defaults: defaults)
    SleepNotifier(store: restartedAgain).consume(
        report([baseline, second]),
        settings: NotificationSettings(notifyOnRelease: true, notifyOnCutout: true),
        post: { delivered.append($0.kind) }
    )
    #expect(delivered == [.released])
}
