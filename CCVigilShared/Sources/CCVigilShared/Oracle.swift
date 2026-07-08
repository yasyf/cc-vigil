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
    case staleActivityMaxAge = "stale-activity-max-age"
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
        // A live machine-driven wait — a run_in_background Bash, an async Task or
        // Workflow, a subagentless Agent, or a waiting tool like Monitor —
        // outranks the human-wait hint. Claude
        // Code fires its idle "waiting for input" Notification the moment such a
        // job detaches from the turn, yet the transcript never advances while it
        // runs, so the block must hold until the job completes or ages out past
        // the max-age backstop. The hint therefore only discounts a session with
        // no machine work pending: a genuinely parked prompt (AskUserQuestion and
        // ExitPlanMode never register as pending) or a leaked session the
        // stale-activity backstop already owns.
        let hint = humanWaitHints[session.sessionPath]
        if !hasMachineDrivenPending(session), let hint, hint > session.lastEventEpoch ?? .min {
            return ([], .humanWaitHint)
        }
        var reasons: [ActivityReason] = []
        if let epoch = session.lastEventEpoch, now - epoch <= Int64(config.activityWindowSeconds) {
            reasons.append(.recentActivity)
        }
        // midTool and waiting carry no natural age cap, so a session whose
        // transcript has not advanced past pendingAsyncMaxAgeSeconds is treated
        // as leaked or dead and discounted. This keeps discovery's mtime window
        // (TranscriptDiscoveryPolicy) and the oracle's active set expressing one
        // policy instead of two that disagree; the claudeProcessesAlive gate
        // stays the primary liveness signal. TODO(cc-notes 0b9f2b5): per-session
        // process liveness (the session's own pid, not the global gate) would
        // remove this age cliff for genuinely-live long tool calls.
        let stale = staleBeyondMaxAge(session, config: config, now: now)
        var discount: DiscountReason?
        if session.midTool {
            if stale {
                discount = .staleActivityMaxAge
            } else {
                reasons.append(.midTool)
            }
        }
        if session.isWaiting {
            if !stale {
                reasons.append(.waiting)
            } else if discount == nil {
                discount = hasOnlyPendingAsync(session) ? .pendingAsyncMaxAge : .staleActivityMaxAge
            }
        }
        return (reasons, discount)
    }

    private func staleBeyondMaxAge(_ session: SessionProbe, config: VigilConfig, now: Int64) -> Bool {
        guard let epoch = session.lastEventEpoch else { return true }
        return now - epoch > Int64(config.pendingAsyncMaxAgeSeconds)
    }

    private func hasOnlyPendingAsync(_ session: SessionProbe) -> Bool {
        !session.pending.isEmpty && session.pending.allSatisfy(\.kind.isPendingAsync)
    }

    private static let machineDrivenKinds: Set<PendingKind> = [
        .waitingTool, .background, .pendingAsyncTask, .pendingAsyncWorkflow, .subagentlessTask,
    ]

    private func hasMachineDrivenPending(_ session: SessionProbe) -> Bool {
        session.pending.contains { Self.machineDrivenKinds.contains($0.kind) }
    }
}
