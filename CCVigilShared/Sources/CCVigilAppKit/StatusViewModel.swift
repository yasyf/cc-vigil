import CCVigilCLIKit
import CCVigilShared
import Foundation

public enum MenuIcon: Equatable, Sendable {
    case disconnected
    case idle
    case blocking
    case latched
    case paused

    public var systemImage: String {
        switch self {
        case .disconnected: "eye.slash"
        case .idle: "eye"
        case .blocking: "eye.fill"
        case .latched: "exclamationmark.triangle.fill"
        case .paused: "pause.circle.fill"
        }
    }
}

public enum PauseMenuAction: Equatable, Sendable {
    case pause
    case resume
}

public enum SessionDisplay {
    public static func name(forTranscriptPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent
        let project = url.deletingLastPathComponent().lastPathComponent
        let trimmedProject = project.hasPrefix("-") ? String(project.dropFirst()) : project
        return "\(trimmedProject) · \(stem.prefix(8))"
    }
}

public struct StatusViewModel: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case statusUpdated(StatusReport)
        case disconnected
    }

    public private(set) var report: StatusReport?

    public init() {}

    public mutating func apply(_ event: Event) {
        switch event {
        case let .statusUpdated(updated):
            report = updated
        case .disconnected:
            report = nil
        }
    }

    public var icon: MenuIcon {
        guard let report else { return .disconnected }
        if !report.latchedCutouts.isEmpty {
            return .latched
        }
        if report.pausedUntil != nil {
            return .paused
        }
        if report.shouldBlock || report.blockApplied {
            return .blocking
        }
        return .idle
    }

    public var canSendCommands: Bool {
        report != nil
    }

    public var pauseAction: PauseMenuAction {
        report?.pausedUntil == nil ? .pause : .resume
    }

    public var activeHolds: [Hold] {
        report?.holds ?? []
    }

    public func headline(now: Date) -> String {
        guard let report else { return "daemon unreachable" }
        if !report.latchedCutouts.isEmpty {
            let kinds = report.latchedCutouts.map(\.rawValue).joined(separator: ", ")
            return "cutout latched: \(kinds)"
        }
        if let until = report.pausedUntil {
            let left = max(0, Int(until.timeIntervalSince(now).rounded()))
            return "paused — \(Durations.text(forSeconds: left)) left"
        }
        if report.shouldBlock {
            let suffix = report.blockApplied ? "" : " (not yet applied)"
            return "keeping the Mac awake\(suffix) — \(reasonSummary(report))"
        }
        if report.blockApplied {
            return "releasing the sleep block"
        }
        return "idle — sleep not blocked"
    }

    public var sessionLines: [String] {
        guard let report else { return [] }
        return report.activeSessions.map { session in
            let reasons = session.reasons.map(\.rawValue).joined(separator: ", ")
            return "\(SessionDisplay.name(forTranscriptPath: session.path)) — \(reasons)"
        }
    }

    public func holdLines(now: Date) -> [String] {
        guard let report else { return [] }
        return report.holds.map { hold in
            let left = max(0, Int(hold.expiresAt.timeIntervalSince(now).rounded()))
            return "\(hold.key) — \(hold.reason) (\(Durations.text(forSeconds: left)) left)"
        }
    }

    private func reasonSummary(_ report: StatusReport) -> String {
        var parts: [String] = []
        if !report.activeSessions.isEmpty {
            let count = report.activeSessions.count
            parts.append(count == 1 ? "1 active session" : "\(count) active sessions")
        }
        if !report.holds.isEmpty {
            let count = report.holds.count
            parts.append(count == 1 ? "1 hold" : "\(count) holds")
        }
        return parts.isEmpty ? "settling" : parts.joined(separator: ", ")
    }
}
