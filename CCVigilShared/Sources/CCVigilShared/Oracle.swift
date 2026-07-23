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
    case backgroundWork = "background-work"
}

public enum DiscountReason: String, Codable, Equatable, Sendable {
    case humanWaitHint = "human-wait-hint"
    case pendingAsyncMaxAge = "pending-async-max-age"
    case staleActivityMaxAge = "stale-activity-max-age"
    case sessionProcessDead = "session-process-dead"
}

public struct ActiveSession: Codable, Equatable, Sendable {
    public let path: String
    public let reasons: [ActivityReason]

    public init(path: String, reasons: [ActivityReason]) {
        self.path = path
        self.reasons = reasons
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(from: decoder, required: ["path", "reasons"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        reasons = try container.decode([ActivityReason].self, forKey: .reasons)
    }
}

public struct SessionDiscount: Codable, Equatable, Sendable {
    public let path: String
    public let reason: DiscountReason

    public init(path: String, reason: DiscountReason) {
        self.path = path
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(from: decoder, required: ["path", "reason"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        reason = try container.decode(DiscountReason.self, forKey: .reason)
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

    public init(from decoder: Decoder) throws {
        try requireExactKeys(from: decoder, required: ["activeSessions", "discounts", "shouldBlock"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shouldBlock = try container.decode(Bool.self, forKey: .shouldBlock)
        activeSessions = try container.decode([ActiveSession].self, forKey: .activeSessions)
        discounts = try container.decode([SessionDiscount].self, forKey: .discounts)
    }
}

public struct OracleState: Equatable, Sendable {
    public let sessions: [SessionProbe]
    public let humanWaitHints: [String: Int64]
    public let backgroundWork: [String: BackgroundWorkReport]
    public let sessionPids: [String: TrackedPid]
    public let claudeProcessesAlive: Bool

    public init(
        sessions: [SessionProbe],
        humanWaitHints: [String: Int64],
        backgroundWork: [String: BackgroundWorkReport],
        sessionPids: [String: TrackedPid],
        claudeProcessesAlive: Bool
    ) {
        self.sessions = sessions
        self.humanWaitHints = humanWaitHints
        self.backgroundWork = backgroundWork
        self.sessionPids = sessionPids
        self.claudeProcessesAlive = claudeProcessesAlive
    }

    public func decision(
        config: VigilConfig,
        clock: some WallClock,
        processStart: (Int32) -> Int64?
    ) -> BlockDecision {
        guard claudeProcessesAlive else {
            return BlockDecision(shouldBlock: false, activeSessions: [], discounts: [])
        }
        let now = Int64(clock.now.timeIntervalSince1970)
        var active: [ActiveSession] = []
        var discounts: [SessionDiscount] = []
        for session in sessions {
            let (reasons, discount) = evaluate(session, now: now, config: config, processStart: processStart)
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
        config: VigilConfig,
        processStart: (Int32) -> Int64?
    ) -> (reasons: [ActivityReason], discount: DiscountReason?) {
        // Per-session liveness (the SessionPidTracker rule): a mapped session
        // whose Claude process is dead is discounted outright — a dead process
        // writes nothing, so not even a recent transcript mtime can vouch for
        // it. Known self-heal window: a --resume'd session keeps its dead old
        // pid until the next nudge remaps it (latest-wins), wrongly discounting
        // it for at most one nudge interval; the global claudeProcessesAlive
        // gate keeps the machine awake while any claude process lives.
        let tracked = sessionPids[session.sessionPath]
        if let tracked, !processLive(tracked, processStart: processStart) {
            return ([], .sessionProcessDead)
        }
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
        //
        // Hook-reported background work is machine-driven pending the transcript
        // cannot see (H2): Stop's background_tasks/session_crons survive across
        // turn boundaries, so the report holds the block through new prompts and
        // idle hints alike, bounded by the same max-age cliff via its own epoch.
        let liveBackgroundWork = backgroundWork[session.sessionPath]
            .map { now - $0.epoch <= Int64(config.pendingAsyncMaxAgeSeconds) } ?? false
        let machineDriven = liveBackgroundWork || hasMachineDrivenPending(session)
        let hint = humanWaitHints[session.sessionPath]
        if !machineDriven, let hint, hint > session.lastEventEpoch ?? .min {
            return ([], .humanWaitHint)
        }
        var reasons: [ActivityReason] = []
        if let epoch = session.lastEventEpoch, now - epoch <= Int64(config.activityWindowSeconds) {
            reasons.append(.recentActivity)
        }
        // midTool and waiting carry no natural age cap, so an unmapped session
        // — one no nudge ever carried a pid for — whose transcript has not
        // advanced past pendingAsyncMaxAgeSeconds is treated as leaked or dead
        // and discounted, keeping discovery's mtime window
        // (TranscriptDiscoveryPolicy) and the oracle's active set expressing one
        // policy instead of two that disagree. For a mapped session the pid
        // verdict replaces this cliff: dead was discounted above, and live holds
        // past it — a genuinely-live process mid-long-work keeps its hold.
        let stale = tracked == nil && staleBeyondMaxAge(session, config: config, now: now)
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
        if liveBackgroundWork {
            reasons.append(.backgroundWork)
        }
        return (reasons, discount)
    }

    private func processLive(_ tracked: TrackedPid, processStart: (Int32) -> Int64?) -> Bool {
        guard let started = processStart(tracked.pid) else { return false }
        // Both sides floored to whole seconds (capturedAtEpoch's units):
        // flooring can only turn a borderline pid-reuse into "live", the safe
        // direction — ambiguity resolves to live so the sleep inhibitor never
        // sleeps the Mac on it.
        return started <= tracked.capturedAtEpoch
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
