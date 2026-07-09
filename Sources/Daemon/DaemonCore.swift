import CCVigilDaemonKit
import CCVigilShared
import Foundation
import os

actor DaemonCore {
    static let reconcileSeconds: TimeInterval = 60
    static let batterySafetyPollSeconds: TimeInterval = 60

    private let config: VigilConfig
    private let clock: SystemClock
    private let oracle: TranscriptOracle
    private let processLister: any ClaudeProcessListing
    private let pusher: any BlockPushing
    private let eventLog: EventLog
    private let stateURL: URL
    private let signal: NudgeSignal
    private let broadcaster: StatusBroadcaster?
    private let thermalReader: (any ThermalReading)?
    private let batterySampler: @Sendable () -> BatteryReading?

    private var hints = HintTracker()
    private var backgroundWork = BackgroundWorkTracker()
    private var holds: HoldRegistry
    private var latch: CutoutLatch
    private var helperLink: HelperLink
    private var pausedUntil: Date?
    private var clearLatch = ClearLatch()
    private var lidClosed = false
    private var battery: BatteryReading?
    private var appliedBlocked = false
    private var pushDecider = PushDecider(reconcileSeconds: DaemonCore.reconcileSeconds)
    private var lastDesired = false
    private var lastBatteryPollAt = Date.distantPast
    private var lastDecision = BlockDecision(shouldBlock: false, activeSessions: [], discounts: [])
    private var lastStatus: StatusReport?

    init(
        config: VigilConfig,
        clock: SystemClock,
        transcriptsRoot: URL,
        processLister: any ClaudeProcessListing,
        pusher: any BlockPushing,
        helperLink: HelperLink,
        eventLog: EventLog,
        stateURL: URL,
        signal: NudgeSignal,
        broadcaster: StatusBroadcaster?,
        thermalReader: (any ThermalReading)?,
        batterySampler: @escaping @Sendable () -> BatteryReading?,
        restoredHolds: HoldRegistry,
        restoredPausedUntil: Date?
    ) {
        self.config = config
        self.clock = clock
        oracle = TranscriptOracle(root: transcriptsRoot)
        self.processLister = processLister
        self.pusher = pusher
        self.helperLink = helperLink
        self.eventLog = eventLog
        self.stateURL = stateURL
        self.signal = signal
        self.broadcaster = broadcaster
        self.thermalReader = thermalReader
        self.batterySampler = batterySampler
        holds = restoredHolds
        latch = CutoutLatch(config: config)
        pausedUntil = restoredPausedUntil
    }

    var pollIntervalSeconds: Double {
        lastDesired || appliedBlocked
            ? Double(config.pollBlockingSeconds)
            : Double(config.pollIdleSeconds)
    }

    func evaluate() async {
        let now = clock.now
        expireHolds()
        expirePause(now: now)
        let decision = collectDecision()
        updateLatch(now: now)
        let activeHolds = holds.active(clock: clock)
        let desired = BlockComposition(
            shouldBlock: decision.shouldBlock,
            hasActiveHolds: !activeHolds.isEmpty,
            paused: pausedUntil != nil,
            latchRejectsAcquire: latch.rejectsAcquire,
            shuttingDown: clearLatch.isClearing
        ).desired
        lastDesired = desired
        await pushIfNeeded(desired: desired, decision: decision, now: now)
        publishStatus()
    }

    func handle(_ request: WireRequest) async -> WireResponse {
        // A stray same-user clear is sticky fail-open until restart; any active
        // work or control op here means this was not an uninstall, so un-latch.
        clearLatch.fold(request)
        switch request {
        case let .nudge(payload):
            hints.apply(payload, now: clock.now)
            backgroundWork.apply(payload, now: clock.now)
            await signal.nudge()
            return .ok
        case .status:
            return .status(statusReport())
        case let .hold(key, reason, ttlSeconds, pid):
            let hold = holds.add(key: key, reason: reason, ttlSeconds: ttlSeconds, pid: pid, clock: clock)
            record(.holdAdded(hold))
            persistState()
            await signal.nudge()
            return .ok
        case let .release(key):
            guard holds.release(key: key) != nil else {
                return .error(message: "no hold with key \(key)")
            }
            record(.holdReleased(key: key))
            persistState()
            await signal.nudge()
            return .ok
        case let .pause(seconds):
            if seconds > 0 {
                let until = clock.now.addingTimeInterval(TimeInterval(seconds))
                pausedUntil = until
                record(.paused(until: until))
            } else {
                pausedUntil = nil
                record(.resumed)
            }
            persistState()
            await signal.nudge()
            return .ok
        case .clear:
            // Uninstall's confirmed teardown: the fold above latched the daemon
            // to stop wanting the block; now push and confirm a settled clear
            // WHILE the helper is still alive and registered, so a transient
            // pmset failure or a SIGKILL-truncated shutdown handler cannot strand
            // disablesleep=1 after bootout.
            let settled = await clearConfirmed()
            await signal.nudge()
            return settled
                ? .ok
                : .error(message: "sleep block did not settle after \(ClearBudget.attempts) attempts")
        case .ping:
            return .ok
        }
    }

    private func clearConfirmed() async -> Bool {
        for attempt in 1 ... ClearBudget.attempts {
            let generation = pushDecider.reassertGeneration
            let outcome = await pusher.push(blocked: false)
            recordPush(outcome, desired: false, generation: generation)
            if case .applied = outcome {
                return true
            }
            Logger.daemon.error(
                """
                clear attempt \(attempt, privacy: .public) did not settle: \
                \(String(describing: outcome), privacy: .public)
                """
            )
            if attempt < ClearBudget.attempts {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return false
    }

    /// Folds a helper push outcome into the daemon's view of the block: the
    /// helper's `applied` verdict settles `appliedBlocked` on a reachable reply,
    /// while the push-decision bookkeeping (pushed-desired latch, reconcile
    /// clock, reassert-generation reentrancy guard) lives in `PushDecider`. A
    /// settled push records the desire; anything else clears the latch so the
    /// next tick retries, and a `forceReassert`/`handleWake` that bumped the
    /// generation mid-await also clears it so the forced re-push survives.
    private func recordPush(_ outcome: BlockPushOutcome, desired: Bool, generation: Int) {
        if helperLink != .dryRun {
            switch outcome {
            case .applied, .unsettled:
                helperLink = .reachable
            case .failed, .unavailable:
                helperLink = .unreachable
            }
        }
        let settled: Bool
        switch outcome {
        case let .applied(applied):
            appliedBlocked = applied
            settled = true
        case let .unsettled(applied, detail):
            appliedBlocked = applied
            settled = false
            Logger.daemon.error("sleep block unsettled: \(detail, privacy: .public)")
        case let .failed(message):
            // The push may still have applied; keep the last known truth and retry.
            settled = false
            Logger.daemon.error("helper push failed: \(message, privacy: .public)")
        case let .unavailable(message):
            settled = false
            Logger.daemon.info("helper unavailable: \(message, privacy: .public)")
        }
        pushDecider.record(desired: desired, settled: settled, generation: generation, at: clock.now)
    }

    func encodedStatus() -> Data? {
        do {
            return try WireCodec.encodePayload(statusReport())
        } catch {
            Logger.daemon.error("status encode failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func updateBattery(_ reading: BatteryReading) async {
        guard reading != battery else { return }
        battery = reading
        await signal.nudge()
    }

    func updateLid(closed: Bool) async {
        guard closed != lidClosed else { return }
        lidClosed = closed
        Logger.daemon.info("lid \(closed ? "closed" : "opened", privacy: .public)")
        record(.lidChanged(closed: closed))
        await signal.nudge()
    }

    func handleWake() async {
        Logger.daemon.info("system powered on: re-asserting and resetting idle baselines")
        record(.wake)
        pushDecider.forceReassert()
        pushDecider.resetReconcileClock()
        lastBatteryPollAt = .distantPast
        await signal.nudge()
    }

    func forceReassert() async {
        pushDecider.forceReassert()
        await signal.nudge()
    }

    func recordStarted(version: String, dryRun: Bool) {
        record(.daemonStarted(version: version, dryRun: dryRun))
    }

    func recordStopped() {
        record(.daemonStopped)
    }

    private func collectDecision() -> BlockDecision {
        let alive = processLister.claudeProcessesAlive()
        var probes: [SessionProbe] = []
        if alive {
            let collection = oracle.collect(config: config, clock: clock)
            for failure in collection.newFailures {
                let detail = "\(failure.path): \(failure.message)"
                Logger.daemon.fault("transcript probe failed, held via last-good/recency \(detail, privacy: .public)")
                record(.probeFailed(path: failure.path, message: failure.message))
            }
            probes = collection.probes
        }
        let paths = probes.map(\.sessionPath)
        let decision = OracleState(
            sessions: probes,
            humanWaitHints: hints.hints(forPaths: paths),
            backgroundWork: backgroundWork.reports(forPaths: paths),
            claudeProcessesAlive: alive
        ).decision(config: config, clock: clock)
        logFreshDiscounts(decision)
        lastDecision = decision
        return decision
    }

    private func updateLatch(now: Date) {
        let blocking = appliedBlocked
        var thermalCelsius: Double?
        if blocking || latch.latched.contains(.thermal) {
            thermalCelsius = thermalReader?.readCelsius()
        }
        if blocking, lidClosed, now.timeIntervalSince(lastBatteryPollAt) >= Self.batterySafetyPollSeconds {
            lastBatteryPollAt = now
            if let sampled = batterySampler() {
                battery = sampled
            }
        }
        let reading = battery ?? BatteryReading(onBattery: false, percent: 100)
        let sample = PowerSample(
            onBattery: reading.onBattery,
            batteryPercent: reading.percent,
            thermalCelsius: thermalCelsius,
            lidClosed: lidClosed,
            blocking: blocking
        )
        for event in latch.update(with: sample) {
            switch event {
            case let .latched(kind):
                Logger.daemon.fault("cutout latched: \(kind.rawValue, privacy: .public)")
                record(.cutoutLatched(kind))
            case let .cleared(kind):
                Logger.daemon.info("cutout cleared: \(kind.rawValue, privacy: .public)")
                record(.cutoutCleared(kind))
            }
        }
    }

    private func pushIfNeeded(desired: Bool, decision: BlockDecision, now: Date) async {
        guard let plan = pushDecider.plan(desired: desired, now: now) else { return }
        let outcome = await pusher.push(blocked: desired)
        recordPush(outcome, desired: desired, generation: plan.generation)
        if plan.edge {
            let detail = "desired=\(desired) applied=\(appliedBlocked)"
                + " sessions=\(decision.activeSessions.count)"
            Logger.daemon.info("block edge: \(detail, privacy: .public)")
            record(.blockEdge(blocked: desired, applied: appliedBlocked, decision: decision))
        }
    }

    private func publishStatus() {
        let status = statusReport()
        guard status != lastStatus else { return }
        lastStatus = status
        guard let broadcaster, let payload = encodedStatus() else { return }
        broadcaster.broadcast(payload)
    }

    private func statusReport() -> StatusReport {
        StatusReport(
            shouldBlock: lastDesired,
            blockApplied: appliedBlocked,
            helper: helperLink,
            activeSessions: lastDecision.activeSessions,
            holds: holds.active(clock: clock),
            latchedCutouts: latch.latched.sorted { $0.rawValue < $1.rawValue },
            pausedUntil: pausedUntil
        )
    }

    private func expireHolds() {
        let expired = holds.prune(clock: clock)
        guard !expired.isEmpty else { return }
        record(.holdsExpired(keys: expired.map(\.key)))
        persistState()
    }

    private func expirePause(now: Date) {
        guard let until = pausedUntil, until <= now else { return }
        pausedUntil = nil
        record(.resumed)
        persistState()
    }

    private func persistState() {
        do {
            try StateStore.save(PersistedState(holds: holds.holds, pausedUntil: pausedUntil), to: stateURL)
        } catch {
            Logger.daemon.fault("state save failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func record(_ event: VigilEvent) {
        do {
            try eventLog.append(EventRecord(at: clock.now, event: event))
        } catch {
            Logger.daemon.fault("event log append failed: \(String(describing: error), privacy: .public)")
        }
    }
}

private extension DaemonCore {
    func logFreshDiscounts(_ decision: BlockDecision) {
        for discount in decision.discounts where !lastDecision.discounts.contains(discount) {
            switch discount.reason {
            case .pendingAsyncMaxAge:
                let detail = "\(discount.path): pending async work with no transcript advance"
                    + " in over \(config.pendingAsyncMaxAgeSeconds)s"
                Logger.daemon.fault(
                    "pending-async max-age backstop discounted \(detail, privacy: .public)"
                )
            case .staleActivityMaxAge:
                let detail = "\(discount.path): mid-tool/waiting session treated as leaked or dead —"
                    + " no transcript advance in over \(config.pendingAsyncMaxAgeSeconds)s"
                Logger.daemon.fault(
                    "stale-activity max-age backstop discounted \(detail, privacy: .public)"
                )
            case .humanWaitHint:
                Logger.daemon.info(
                    "human-wait hint discounted \(discount.path, privacy: .public)"
                )
            }
        }
    }
}
