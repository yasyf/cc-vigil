import CCVigilAppKit
import CCVigilShared
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_767_000_000)
private let atEpoch = Int64(now.timeIntervalSince1970)
private let releasedAt = now.formatted(date: .omitted, time: .shortened)

private extension NotificationSettings {
    static let both = NotificationSettings(notifyOnRelease: true, notifyOnCutout: true)
}

private final class FakeWatermarkStore: AlertWatermarkStore, @unchecked Sendable {
    private(set) var lastSeenAlertId: Int64?

    init(lastSeenAlertId: Int64? = nil) {
        self.lastSeenAlertId = lastSeenAlertId
    }

    func recordSeen(_ id: Int64) {
        lastSeenAlertId = id
    }
}

private func released(id: Int64, sessions: Int, holds: Int) -> SleepAlert {
    SleepAlert(id: id, atEpoch: atEpoch, payload: .released(sessions: sessions, holds: holds))
}

private func cutout(id: Int64, _ kinds: [CutoutKind]) -> SleepAlert {
    SleepAlert(id: id, atEpoch: atEpoch, payload: .cutoutLatched(kinds: kinds))
}

/// The daemon rides the recent-alert ring on every StatusReport, and encodes an
/// empty ring as `nil` alerts; these helpers mirror that wire shape exactly.
private func report(alerts: [SleepAlert]?) -> StatusReport {
    StatusReport(
        shouldBlock: false,
        blockApplied: false,
        helper: .reachable,
        activeSessions: [],
        holds: [],
        latchedCutouts: [],
        pausedUntil: nil,
        alerts: alerts
    )
}

private func consume(
    _ reports: [StatusReport],
    store: FakeWatermarkStore,
    settings: NotificationSettings = .both
) -> [[SleepNotification]] {
    let notifier = SleepNotifier(store: store)
    return reports.map { notifier.consume(.statusUpdated($0), settings: settings) }
}

private let releasedToast = SleepNotification(
    kind: .released,
    title: "Agents finished",
    body: "The Mac may sleep now — 1 active session and 1 hold finished at \(releasedAt)."
)

private let cutoutToast = SleepNotification(
    kind: .cutoutLatched,
    title: "Sleep protection dropped",
    body: "Battery cutout latched — the Mac may sleep despite active agents."
)

/// First-run choice: a fresh install must NOT replay the daemon's whole recent
/// ring as a burst of toasts. With no stored watermark, the consumer adopts the
/// newest id in its first report as the baseline and posts nothing; only alerts
/// minted after that baseline surface.
@Test func firstRunAdoptsNewestAlertWithoutReplayingTheRing() {
    let store = FakeWatermarkStore()
    let ring = [
        released(id: 1, sessions: 1, holds: 1),
        cutout(id: 2, [.battery]),
        released(id: 3, sessions: 2, holds: 0),
    ]
    let results = consume([report(alerts: ring)], store: store)
    #expect(results == [[]])
    #expect(store.lastSeenAlertId == 3)
}

@Test func firstRunSkipsHistoryThenPostsOnlyAlertsNewerThanTheBaseline() {
    let store = FakeWatermarkStore()
    let base = [released(id: 1, sessions: 1, holds: 1)]
    let grown = base + [released(id: 2, sessions: 1, holds: 1)]
    let results = consume([report(alerts: base), report(alerts: grown)], store: store)
    #expect(results == [[], [releasedToast]])
    #expect(store.lastSeenAlertId == 2)
}

@Test func duplicatePushDeliversEachAlertExactlyOnce() {
    let store = FakeWatermarkStore()
    let base = [released(id: 1, sessions: 1, holds: 1)]
    let grown = base + [cutout(id: 2, [.battery])]
    let results = consume(
        [report(alerts: base), report(alerts: grown), report(alerts: grown)],
        store: store
    )
    #expect(results == [[], [cutoutToast], []])
    #expect(store.lastSeenAlertId == 2)
}

@Test func reconnectReDeliversTheRingWithoutRePosting() {
    let store = FakeWatermarkStore()
    let base = [released(id: 1, sessions: 1, holds: 1)]
    let grown = base + [cutout(id: 2, [.battery])]
    let notifier = SleepNotifier(store: store)
    _ = notifier.consume(.statusUpdated(report(alerts: base)), settings: .both)
    let posted = notifier.consume(.statusUpdated(report(alerts: grown)), settings: .both)
    let afterDrop = notifier.consume(.disconnected, settings: .both)
    let afterReconnect = notifier.consume(.statusUpdated(report(alerts: grown)), settings: .both)
    #expect(posted == [cutoutToast])
    #expect(afterDrop == [])
    #expect(afterReconnect == [])
    #expect(store.lastSeenAlertId == 2)
}

@Test func appRestartResumesFromPersistedWatermark() {
    let store = FakeWatermarkStore()
    let ring = [released(id: 1, sessions: 1, holds: 1), cutout(id: 2, [.battery])]
    _ = SleepNotifier(store: store).consume(.statusUpdated(report(alerts: ring)), settings: .both)
    #expect(store.lastSeenAlertId == 2)
    let afterRestart = SleepNotifier(store: store)
        .consume(.statusUpdated(report(alerts: ring)), settings: .both)
    #expect(afterRestart == [])
    #expect(store.lastSeenAlertId == 2)
}

@Test func postsFreshAlertsSortedByIdRegardlessOfArrayOrder() {
    let store = FakeWatermarkStore()
    let base = [released(id: 1, sessions: 1, holds: 1)]
    let grown = [
        released(id: 3, sessions: 2, holds: 0),
        released(id: 1, sessions: 1, holds: 1),
        cutout(id: 2, [.battery]),
    ]
    let results = consume([report(alerts: base), report(alerts: grown)], store: store)
    let releasedTwoSessions = SleepNotification(
        kind: .released,
        title: "Agents finished",
        body: "The Mac may sleep now — 2 active sessions finished at \(releasedAt)."
    )
    #expect(results == [[], [cutoutToast, releasedTwoSessions]])
    #expect(store.lastSeenAlertId == 3)
}

@Test func cutoutBodyNamesEveryLatchedKind() {
    let store = FakeWatermarkStore()
    let base = [released(id: 1, sessions: 1, holds: 1)]
    let grown = base + [cutout(id: 2, [.thermal, .battery])]
    let results = consume([report(alerts: base), report(alerts: grown)], store: store)
    #expect(results[1] == [SleepNotification(
        kind: .cutoutLatched,
        title: "Sleep protection dropped",
        body: "Battery and thermal cutouts latched — the Mac may sleep despite active agents."
    )])
}

@Test func releaseToggleOffSuppressesReleaseButStillAdvancesWatermark() {
    let store = FakeWatermarkStore()
    let base = [cutout(id: 1, [.battery])]
    let grown = base + [released(id: 2, sessions: 1, holds: 1)]
    let results = consume(
        [report(alerts: base), report(alerts: grown)],
        store: store,
        settings: NotificationSettings(notifyOnRelease: false, notifyOnCutout: true)
    )
    #expect(results == [[], []])
    #expect(store.lastSeenAlertId == 2)
}

@Test func gatingPostsOnlyEnabledKindsWithinASingleReport() {
    let store = FakeWatermarkStore()
    let base = [released(id: 1, sessions: 1, holds: 1)]
    let grown = base + [
        released(id: 2, sessions: 1, holds: 1),
        cutout(id: 3, [.battery]),
    ]
    let results = consume(
        [report(alerts: base), report(alerts: grown)],
        store: store,
        settings: NotificationSettings(notifyOnRelease: true, notifyOnCutout: false)
    )
    #expect(results == [[], [releasedToast]])
    #expect(store.lastSeenAlertId == 3)
}

@Test func nilAlertsReportPostsNothingAndLeavesTheWatermark() {
    let store = FakeWatermarkStore()
    let ring = [released(id: 1, sessions: 1, holds: 1), cutout(id: 2, [.battery])]
    _ = SleepNotifier(store: store).consume(.statusUpdated(report(alerts: ring)), settings: .both)
    #expect(store.lastSeenAlertId == 2)
    let notifier = SleepNotifier(store: store)
    #expect(notifier.consume(.statusUpdated(report(alerts: nil)), settings: .both) == [])
    #expect(store.lastSeenAlertId == 2)
    #expect(notifier.consume(.statusUpdated(report(alerts: ring)), settings: .both) == [])
    #expect(store.lastSeenAlertId == 2)
}

@Test func nilAlertsBeforeAnyWatermarkStaysUninitialised() {
    let store = FakeWatermarkStore()
    let result = consume([report(alerts: nil)], store: store)
    #expect(result == [[]])
    #expect(store.lastSeenAlertId == nil)
}
