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
public struct SleepNotifier: Equatable, Sendable {
    private var previous: StatusReport?
    private var lastBlocking: StatusReport?

    public init() {}

    public mutating func detect(
        _ event: StatusViewModel.Event,
        settings: NotificationSettings,
        now: Date
    ) -> [SleepNotification] {
        switch event {
        case .disconnected:
            previous = nil
            lastBlocking = nil
            return []
        case let .statusUpdated(report):
            defer {
                previous = report
                if report.shouldBlock {
                    lastBlocking = report
                }
            }
            guard let previous else { return [] }
            let newlyLatched = report.latchedCutouts.filter { !previous.latchedCutouts.contains($0) }
            var notifications: [SleepNotification] = []
            if settings.notifyOnCutout, previous.shouldBlock, !newlyLatched.isEmpty {
                notifications.append(Self.cutoutLatched(newlyLatched))
            }
            if settings.notifyOnRelease,
               previous.blockApplied,
               !report.blockApplied,
               !report.shouldBlock,
               report.pausedUntil == nil,
               newlyLatched.isEmpty,
               let lastBlocking
            {
                notifications.append(Self.released(lastBlocking, now: now))
            }
            return notifications
        }
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
