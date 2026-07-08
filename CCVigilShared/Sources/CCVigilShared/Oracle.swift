import Foundation

public enum PendingKind: String, Codable, Equatable, Sendable, CaseIterable {
    case waitingTool = "waiting_tool"
    case background
    case subagentlessTask = "subagentless_task"
    case pendingAsyncTask = "pending_async_task"
    case pendingAsyncWorkflow = "pending_async_workflow"
    case midTool = "mid_tool"

    public var isPendingAsync: Bool {
        self == .pendingAsyncTask || self == .pendingAsyncWorkflow
    }
}

public struct PendingItem: Codable, Equatable, Sendable {
    public let toolUseID: String?
    public let name: String
    public let kind: PendingKind

    public init(toolUseID: String?, name: String, kind: PendingKind) {
        self.toolUseID = toolUseID
        self.name = name
        self.kind = kind
    }
}

public struct SessionProbe: Codable, Equatable, Sendable {
    public let sessionPath: String
    public let isWaiting: Bool
    public let midTool: Bool
    public let lastEventEpoch: Int64?
    public let pending: [PendingItem]

    public init(
        sessionPath: String,
        isWaiting: Bool,
        midTool: Bool,
        lastEventEpoch: Int64?,
        pending: [PendingItem]
    ) {
        self.sessionPath = sessionPath
        self.isWaiting = isWaiting
        self.midTool = midTool
        self.lastEventEpoch = lastEventEpoch
        self.pending = pending
    }
}

public enum ActivityReason: String, Codable, Equatable, Sendable {
    case recentActivity = "recent-activity"
    case midTool = "mid-tool"
    case waiting
}

public enum DiscountReason: String, Codable, Equatable, Sendable {
    case humanWaitHint = "human-wait-hint"
    case pendingAsyncMaxAge = "pending-async-max-age"
}

public struct ActiveSession: Codable, Equatable, Sendable {
    public let path: String
    public let reasons: [ActivityReason]

    public init(path: String, reasons: [ActivityReason]) {
        self.path = path
        self.reasons = reasons
    }
}

public struct SessionDiscount: Codable, Equatable, Sendable {
    public let path: String
    public let reason: DiscountReason

    public init(path: String, reason: DiscountReason) {
        self.path = path
        self.reason = reason
    }
}

public struct BlockDecision: Codable, Equatable, Sendable {
    public let shouldBlock: Bool
    public let activeSessions: [ActiveSession]
    public let discounts: [SessionDiscount]

    public init(shouldBlock: Bool, activeSessions: [ActiveSession], discounts: [SessionDiscount]) {
        self.shouldBlock = shouldBlock
        self.activeSessions = activeSessions
        self.discounts = discounts
    }
}

public struct OracleState: Equatable, Sendable {
    public let sessions: [SessionProbe]
    public let humanWaitHints: [String: Int64]
    public let claudeProcessesAlive: Bool

    public init(sessions: [SessionProbe], humanWaitHints: [String: Int64], claudeProcessesAlive: Bool) {
        self.sessions = sessions
        self.humanWaitHints = humanWaitHints
        self.claudeProcessesAlive = claudeProcessesAlive
    }

    public func decision(config: VigilConfig, clock: some WallClock) -> BlockDecision {
        guard claudeProcessesAlive else {
            return BlockDecision(shouldBlock: false, activeSessions: [], discounts: [])
        }
        let now = Int64(clock.now.timeIntervalSince1970)
        var active: [ActiveSession] = []
        var discounts: [SessionDiscount] = []
        for session in sessions {
            let (reasons, discount) = evaluate(session, now: now, config: config)
            if !reasons.isEmpty {
                active.append(ActiveSession(path: session.sessionPath, reasons: reasons))
            }
            if let discount {
                discounts.append(SessionDiscount(path: session.sessionPath, reason: discount))
            }
        }
        return BlockDecision(shouldBlock: !active.isEmpty, activeSessions: active, discounts: discounts)
    }

    private func evaluate(
        _ session: SessionProbe,
        now: Int64,
        config: VigilConfig
    ) -> (reasons: [ActivityReason], discount: DiscountReason?) {
        if let hint = humanWaitHints[session.sessionPath], hint > session.lastEventEpoch ?? .min {
            return ([], .humanWaitHint)
        }
        var reasons: [ActivityReason] = []
        if let epoch = session.lastEventEpoch, now - epoch <= Int64(config.activityWindowSeconds) {
            reasons.append(.recentActivity)
        }
        if session.midTool {
            reasons.append(.midTool)
        }
        var discount: DiscountReason?
        if session.isWaiting {
            if hasOnlyStalePendingAsync(session, now: now, config: config) {
                discount = .pendingAsyncMaxAge
            } else {
                reasons.append(.waiting)
            }
        }
        return (reasons, discount)
    }

    private func hasOnlyStalePendingAsync(_ session: SessionProbe, now: Int64, config: VigilConfig) -> Bool {
        guard !session.pending.isEmpty, session.pending.allSatisfy(\.kind.isPendingAsync) else {
            return false
        }
        guard let epoch = session.lastEventEpoch else { return true }
        return now - epoch > Int64(config.pendingAsyncMaxAgeSeconds)
    }
}
