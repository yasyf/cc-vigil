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

/// Records the interleaving of post and recordSeen calls so a test can pin that
/// the watermark advances only after every alert in a report has been posted.
private final class OrderLog: @unchecked Sendable {
    enum Step: Equatable {
        case post(SleepNotification.Kind)
        case record(Int64)
    }

    private(set) var steps: [Step] = []

    func post(_ notification: SleepNotification) {
        steps.append(.post(notification.kind))
    }

    func record(_ id: Int64) {
        steps.append(.record(id))
    }
}

private final class SpyWatermarkStore: AlertWatermarkStore, @unchecked Sendable {
    private(set) var lastSeenAlertId: Int64?
    private let log: OrderLog

    init(lastSeenAlertId: Int64?, log: OrderLog) {
        self.lastSeenAlertId = lastSeenAlertId
        self.log = log
    }

    func recordSeen(_ id: Int64) {
        log.record(id)
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

private func posted(
    _ notifier: SleepNotifier,
    _ event: StatusViewModel.Event,
    settings: NotificationSettings = .both
) -> [SleepNotification] {
    var out: [SleepNotification] = []
    notifier.consume(event, settings: settings) { out.append($0) }
    return out
}

private func consume(
    _ reports: [StatusReport],
    store: FakeWatermarkStore,
    settings: NotificationSettings = .both
) -> [[SleepNotification]] {
    let notifier = SleepNotifier(store: store)
    return reports.map { posted(notifier, .statusUpdated($0), settings: settings) }
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
    _ = posted(notifier, .statusUpdated(report(alerts: base)))
    let firstPost = posted(notifier, .statusUpdated(report(alerts: grown)))
    let afterDrop = posted(notifier, .disconnected)
    let afterReconnect = posted(notifier, .statusUpdated(report(alerts: grown)))
    #expect(firstPost == [cutoutToast])
    #expect(afterDrop == [])
    #expect(afterReconnect == [])
    #expect(store.lastSeenAlertId == 2)
}

@Test func appRestartResumesFromPersistedWatermark() {
    let store = FakeWatermarkStore()
    let ring = [released(id: 1, sessions: 1, holds: 1), cutout(id: 2, [.battery])]
    _ = posted(SleepNotifier(store: store), .statusUpdated(report(alerts: ring)))
    #expect(store.lastSeenAlertId == 2)
    let afterRestart = posted(SleepNotifier(store: store), .statusUpdated(report(alerts: ring)))
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
    _ = posted(SleepNotifier(store: store), .statusUpdated(report(alerts: ring)))
    #expect(store.lastSeenAlertId == 2)
    let notifier = SleepNotifier(store: store)
    #expect(posted(notifier, .statusUpdated(report(alerts: nil))) == [])
    #expect(store.lastSeenAlertId == 2)
    #expect(posted(notifier, .statusUpdated(report(alerts: ring))) == [])
    #expect(store.lastSeenAlertId == 2)
}

@Test func nilAlertsBeforeAnyWatermarkStaysUninitialised() {
    let store = FakeWatermarkStore()
    let result = consume([report(alerts: nil)], store: store)
    #expect(result == [[]])
    #expect(store.lastSeenAlertId == nil)
}

/// A stale report re-delivering an OLDER ring (an out-of-order push around a
/// reconnect) must never drag the watermark backward; otherwise already-seen
/// alerts re-post as duplicates once the ring re-advances.
@Test func staleOlderRingNeverDragsTheWatermarkBackward() {
    let store = FakeWatermarkStore()
    let notifier = SleepNotifier(store: store)
    let ringFiveSix = [released(id: 5, sessions: 1, holds: 1), released(id: 6, sessions: 1, holds: 1)]
    #expect(posted(notifier, .statusUpdated(report(alerts: ringFiveSix))) == [])
    #expect(store.lastSeenAlertId == 6)

    let staleRingThreeFour = [released(id: 3, sessions: 1, holds: 1), released(id: 4, sessions: 1, holds: 1)]
    #expect(posted(notifier, .statusUpdated(report(alerts: staleRingThreeFour))) == [])
    #expect(store.lastSeenAlertId == 6)

    let ringSeven = [released(id: 7, sessions: 1, holds: 1)]
    #expect(posted(notifier, .statusUpdated(report(alerts: ringSeven))) == [releasedToast])
    #expect(store.lastSeenAlertId == 7)
}

/// A crash mid-tick must re-post rather than silently drop, so the watermark is
/// persisted only after every alert in the report has been handed to the poster.
@Test func advancesWatermarkOnlyAfterPostingEveryAlert() {
    let log = OrderLog()
    let store = SpyWatermarkStore(lastSeenAlertId: 1, log: log)
    let notifier = SleepNotifier(store: store)
    let ring = [
        released(id: 1, sessions: 1, holds: 1),
        cutout(id: 2, [.battery]),
        released(id: 3, sessions: 2, holds: 0),
    ]
    notifier.consume(.statusUpdated(report(alerts: ring)), settings: .both) { log.post($0) }
    #expect(log.steps == [.post(.cutoutLatched), .post(.released), .record(3)])
    #expect(store.lastSeenAlertId == 3)
}
