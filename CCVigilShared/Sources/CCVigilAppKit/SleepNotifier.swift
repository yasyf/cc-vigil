import CCVigilShared
import Foundation

public struct NotificationSettings: Equatable, Sendable {
    public let notifyOnRelease: Bool
    public let notifyOnCutout: Bool

    public init(notifyOnRelease: Bool, notifyOnCutout: Bool) {
        self.notifyOnRelease = notifyOnRelease
        self.notifyOnCutout = notifyOnCutout
    }
}

public struct SleepNotification: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case released
        case cutoutLatched
    }

    public let kind: Kind
    public let title: String
    public let body: String

    public init(kind: Kind, title: String, body: String) {
        self.kind = kind
        self.title = title
        self.body = body
    }
}

/// Persists the id of the newest daemon alert the App has already decided about.
/// It is the App's whole memory of the alert stream — surviving XPC reconnects
/// and app restarts — so replay is exactly-once. The concrete store keeps it in
/// UserDefaults; tests supply an in-memory double.
public protocol AlertWatermarkStore: AnyObject, Sendable {
    var lastSeenAlertId: Int64? { get }
    func recordSeen(_ id: Int64)
}

/// UserDefaults-backed watermark, matching how the App layer persists its other
/// preferences (a string key on the standard suite). Absence is the first-run
/// signal, so the key is read through `object(forKey:)` rather than the
/// zero-defaulting `integer(forKey:)`.
public final class UserDefaultsAlertWatermarkStore: AlertWatermarkStore, @unchecked Sendable {
    private static let key = "lastSeenSleepAlertId"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastSeenAlertId: Int64? {
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        return Int64(defaults.integer(forKey: Self.key))
    }

    public func recordSeen(_ id: Int64) {
        defaults.set(Int(id), forKey: Self.key)
    }
}

/// Replays the daemon's composed sleep-alert stream into user-facing toasts,
/// exactly once each. The daemon's SleepAlertComposer mints every release and
/// cutout edge from its own unbroken status stream and rides the recent-alert
/// ring on each StatusReport; this consumer posts the alerts newer than its
/// persisted watermark, in id order, then advances the watermark — never
/// backward, so a stale report re-delivering an older ring replays nothing.
/// Duplicate pushes, an XPC reconnect, and an app restart are all no-ops for
/// alerts already seen, and a report whose ring the daemon encoded as `nil`
/// (an old daemon during upgrade skew) leaves the watermark untouched. The
/// toast copy and NotificationSettings gating are the App's job, applied here
/// at post time keyed off each alert's kind.
///
/// Residuals, by design: alerts older than the daemon's ring cap age out
/// before a long-absent App sees them, and an edge that both begins and
/// resolves inside a daemon restart is never minted at all — the away summary,
/// built from events.log, remains the ground truth that surfaces both. A
/// daemon whose id counter regressed (state.json rewritten by an older
/// daemon) mints ids below the watermark and those toasts stay suppressed
/// until the counter passes it again.
public struct SleepNotifier {
    private let store: any AlertWatermarkStore

    public init(store: any AlertWatermarkStore) {
        self.store = store
    }

    /// Callers serialize consume() — the app invokes it from the @MainActor status stream — so the check-then-advance watermark update needs no internal synchronization.
    public func consume(
        _ event: StatusViewModel.Event,
        settings: NotificationSettings,
        post: (SleepNotification) -> Void
    ) {
        guard case let .statusUpdated(report) = event, let alerts = report.alerts else { return }
        let newest = alerts.map(\.id).max()
        guard let watermark = store.lastSeenAlertId else {
            // First run: adopt the ring's newest id as the baseline rather than
            // replaying the whole ring as a burst of toasts.
            newest.map(store.recordSeen)
            return
        }
        let fresh = alerts.filter { $0.id > watermark }.sorted { $0.id < $1.id }
        for alert in fresh {
            if let notification = Self.notification(for: alert, settings: settings) {
                post(notification)
            }
        }
        if let newest, newest > watermark {
            store.recordSeen(newest)
        }
    }

    private static func notification(
        for alert: SleepAlert,
        settings: NotificationSettings
    ) -> SleepNotification? {
        switch alert.payload {
        case let .released(sessions, holds):
            guard settings.notifyOnRelease else { return nil }
            return released(sessions: sessions, holds: holds, atEpoch: alert.atEpoch)
        case let .cutoutLatched(kinds):
            guard settings.notifyOnCutout else { return nil }
            return cutoutLatched(kinds)
        }
    }

    private static func released(sessions: Int, holds: Int, atEpoch: Int64) -> SleepNotification {
        let summary = holdingSummary(sessions: sessions, holds: holds)
        let time = Date(timeIntervalSince1970: TimeInterval(atEpoch))
            .formatted(date: .omitted, time: .shortened)
        return SleepNotification(
            kind: .released,
            title: "Agents finished",
            body: "The Mac may sleep now — \(summary) finished at \(time)."
        )
    }

    private static func cutoutLatched(_ kinds: [CutoutKind]) -> SleepNotification {
        let names = kinds.map(\.rawValue).sorted()
        let noun = names.count == 1 ? "cutout" : "cutouts"
        let sentence = "\(names.joined(separator: " and ")) \(noun) latched"
            + " — the Mac may sleep despite active agents."
        return SleepNotification(
            kind: .cutoutLatched,
            title: "Sleep protection dropped",
            body: sentence.prefix(1).uppercased() + sentence.dropFirst()
        )
    }

    private static func holdingSummary(sessions: Int, holds: Int) -> String {
        var parts: [String] = []
        if sessions > 0 {
            parts.append(sessions == 1 ? "1 active session" : "\(sessions) active sessions")
        }
        if holds > 0 {
            parts.append(holds == 1 ? "1 hold" : "\(holds) holds")
        }
        return parts.joined(separator: " and ")
    }
}
