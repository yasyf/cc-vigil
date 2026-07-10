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

/// Detects the two user-facing edges in the daemon's status stream — the block
/// releasing because agents finished, and a cutout latching mid-block — and
/// builds their notification content. State-tracking only; the App layer posts.
///
/// Known limits: edges that both begin and resolve inside an XPC disconnect gap
/// can misfire or go unseen — the snapshot stream cannot reconstruct causality
/// across the gap, and a clean fix needs daemon-side alert telemetry. The
/// daemon's events.log remains the ground truth; the away summary surfaces
/// anything these toasts miss.
///
/// Residual (superseded daemon-side by SleepAlertComposer, which now mints these
/// edges from the daemon's unbroken stream onto the StatusReport alert ring):
/// only alerts older than that ring still fall through to the away summary.
public struct SleepNotifier: Equatable, Sendable {
    private var previous: StatusReport?
    private var lastBlocking: StatusReport?
    private var alertedCutouts: Set<CutoutKind> = []

    public init() {}

    public mutating func detect(
        _ event: StatusViewModel.Event,
        settings: NotificationSettings,
        now: Date
    ) -> [SleepNotification] {
        switch event {
        case .disconnected:
            previous = nil
            return []
        case let .statusUpdated(report):
            defer {
                if report.shouldBlock {
                    lastBlocking = report
                } else if report.isFullyIdle {
                    lastBlocking = nil
                }
                previous = report
                alertedCutouts.formIntersection(report.latchedCutouts)
            }
            var notifications: [SleepNotification] = []
            if settings.notifyOnCutout {
                let firing = report.latchedCutouts.filter { !alertedCutouts.contains($0) }
                if !firing.isEmpty, cutoutInterruptedWork(report) {
                    alertedCutouts.formUnion(firing)
                    notifications.append(Self.cutoutLatched(firing))
                }
            }
            if settings.notifyOnRelease,
               let previous,
               previous.blockApplied,
               !report.blockApplied,
               !report.shouldBlock,
               report.pausedUntil == nil,
               report.latchedCutouts.isEmpty,
               report.activeSessions.isEmpty,
               report.holds.isEmpty,
               let lastBlocking
            {
                notifications.append(Self.released(lastBlocking, now: now))
            }
            return notifications
        }
    }

    private func cutoutInterruptedWork(_ report: StatusReport) -> Bool {
        if let previous {
            return previous.shouldBlock
        }
        return report.hasActiveWork || lastBlocking != nil
    }

    private static func released(_ blocking: StatusReport, now: Date) -> SleepNotification {
        let summary = holdingSummary(sessions: blocking.activeSessions.count, holds: blocking.holds.count)
        let time = now.formatted(date: .omitted, time: .shortened)
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

private extension StatusReport {
    var isFullyIdle: Bool {
        !shouldBlock && !blockApplied
            && activeSessions.isEmpty && holds.isEmpty && latchedCutouts.isEmpty
    }

    var hasActiveWork: Bool {
        !activeSessions.isEmpty || !holds.isEmpty
    }
}
