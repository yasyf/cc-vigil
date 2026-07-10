import Foundation

/// Composes the daemon's user-facing sleep alerts from its own unbroken status
/// stream, stamping each with a monotonic id drawn from a persisted counter.
/// It ports SleepNotifier's edge gating — a block releasing into a truly-idle
/// Mac, a cutout latching mid-work, a cutout un-latch re-arming — but, feeding
/// on the daemon's own reports, it never loses the causal thread across an XPC
/// gap the way the App layer does. That is the entire point: the daemon never
/// disconnects from itself, so `previous`-state tracking is trustworthy and
/// each edge is seen exactly once, at its source.
/// The alerted-cutout set persists with the counter and ring, so a daemon
/// restart does not re-announce a cutout still latched from before it.
public struct SleepAlertComposer: Equatable, Sendable {
    public private(set) var nextAlertId: Int64
    public private(set) var recentAlerts: [SleepAlert]
    public private(set) var alertedCutouts: Set<CutoutKind>

    private let cap: Int
    private var previous: StatusReport?
    private var lastBlocking: StatusReport?

    public init(
        nextAlertId: Int64 = 1,
        recentAlerts: [SleepAlert] = [],
        alertedCutouts: Set<CutoutKind> = [],
        cap: Int = 32
    ) {
        self.nextAlertId = nextAlertId
        self.recentAlerts = recentAlerts
        self.alertedCutouts = alertedCutouts
        self.cap = cap
    }

    public mutating func ingest(_ report: StatusReport, now: Date) -> [SleepAlert] {
        defer {
            if report.shouldBlock {
                lastBlocking = report
            } else if report.isFullyIdle {
                lastBlocking = nil
            }
            previous = report
            alertedCutouts.formIntersection(report.latchedCutouts)
        }
        var emitted: [SleepAlert] = []
        let firing = report.latchedCutouts.filter { !alertedCutouts.contains($0) }
        if !firing.isEmpty, cutoutInterruptedWork(report) {
            alertedCutouts.formUnion(firing)
            emitted.append(makeAlert(
                .cutoutLatched(kinds: firing.sorted { $0.rawValue < $1.rawValue }),
                now: now
            ))
        }
        if let previous,
           previous.blockApplied,
           !report.blockApplied,
           !report.shouldBlock,
           report.pausedUntil == nil,
           report.latchedCutouts.isEmpty,
           report.activeSessions.isEmpty,
           report.holds.isEmpty,
           let lastBlocking
        {
            emitted.append(makeAlert(
                .released(sessions: lastBlocking.activeSessions.count, holds: lastBlocking.holds.count),
                now: now
            ))
        }
        recentAlerts.append(contentsOf: emitted)
        if recentAlerts.count > cap {
            recentAlerts.removeFirst(recentAlerts.count - cap)
        }
        return emitted
    }

    private mutating func makeAlert(_ payload: SleepAlert.Payload, now: Date) -> SleepAlert {
        let alert = SleepAlert(id: nextAlertId, atEpoch: Int64(now.timeIntervalSince1970), payload: payload)
        nextAlertId += 1
        return alert
    }

    private func cutoutInterruptedWork(_ report: StatusReport) -> Bool {
        if let previous {
            return previous.shouldBlock
        }
        return report.hasActiveWork || lastBlocking != nil
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
