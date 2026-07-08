import CCVigilShared
import Foundation

public enum StatusRenderError: Error, CustomStringConvertible {
    case notUTF8

    public var description: String {
        "status JSON is not UTF-8"
    }
}

public enum StatusRenderer {
    public static func render(_ report: StatusReport, now: Date) -> String {
        var lines = [
            "blocking: \(blockingText(report))",
            "helper: \(report.helper.rawValue)",
            "paused: \(report.pausedUntil.map { "until \(timestamp($0))" } ?? "no")",
            "cutouts: \(listText(report.latchedCutouts.map(\.rawValue)))",
        ]
        if report.activeSessions.isEmpty {
            lines.append("sessions: (none)")
        } else {
            lines.append("sessions:")
            for session in report.activeSessions {
                let reasons = session.reasons.map(\.rawValue).joined(separator: ", ")
                lines.append("  \(session.path) — \(reasons)")
            }
        }
        if report.holds.isEmpty {
            lines.append("holds: (none)")
        } else {
            lines.append("holds:")
            for hold in report.holds {
                let remaining = max(0, Int(hold.expiresAt.timeIntervalSince(now).rounded()))
                let expiry = Durations.text(forSeconds: remaining)
                lines.append("  \(hold.key) — \(hold.reason) (expires in \(expiry))")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func renderJSON(_ report: StatusReport) throws -> String {
        let payload = try WireCodec.encodePayload(report)
        guard let text = String(data: payload, encoding: .utf8) else {
            throw StatusRenderError.notUTF8
        }
        return text
    }

    private static func blockingText(_ report: StatusReport) -> String {
        switch (report.shouldBlock, report.blockApplied) {
        case (true, true): "yes (applied)"
        case (true, false): "yes (not yet applied)"
        case (false, true): "no (still applied)"
        case (false, false): "no"
        }
    }

    private static func listText(_ items: [String]) -> String {
        items.isEmpty ? "(none)" : items.joined(separator: ", ")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
