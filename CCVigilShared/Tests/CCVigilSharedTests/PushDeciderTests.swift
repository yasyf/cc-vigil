import CCVigilShared
import Foundation
import Testing

private let epoch = Date(timeIntervalSince1970: 1_000_000)

@Test func firstPlanIsAnEdgeFromTheUnknownState() {
    let decider = PushDecider(reconcileSeconds: 60)
    let plan = decider.plan(desired: false, now: epoch)
    #expect(plan?.edge == true)
    #expect(plan?.reconcile == false)
}

@Test func edgeFiresOnDesiredTransitionAndSettledPushSuppressesTheRepeat() throws {
    var decider = PushDecider(reconcileSeconds: 60)

    let open = decider.plan(desired: true, now: epoch)
    #expect(open?.edge == true)
    try decider.record(desired: true, settled: true, generation: #require(open?.generation), at: epoch)

    #expect(decider.plan(desired: true, now: epoch) == nil)

    let flip = decider.plan(desired: false, now: epoch)
    #expect(flip?.edge == true)
}

@Test func reconcileRepushesExactlyAtTheSixtySecondBoundary() throws {
    var decider = PushDecider(reconcileSeconds: 60)
    let open = decider.plan(desired: true, now: epoch)
    try decider.record(desired: true, settled: true, generation: #require(open?.generation), at: epoch)

    #expect(decider.plan(desired: true, now: epoch.addingTimeInterval(59)) == nil)

    let boundary = decider.plan(desired: true, now: epoch.addingTimeInterval(60))
    #expect(boundary != nil)
    #expect(boundary?.edge == false)
    #expect(boundary?.reconcile == true)
}

@Test func idleNeverReconcilesNoMatterHowMuchTimePasses() throws {
    var decider = PushDecider(reconcileSeconds: 60)
    let open = decider.plan(desired: false, now: epoch)
    try decider.record(desired: false, settled: true, generation: #require(open?.generation), at: epoch)
    #expect(decider.plan(desired: false, now: epoch.addingTimeInterval(3600)) == nil)
}

@Test func unsettledPushClearsTheLatchSoTheNextTickRetries() throws {
    var decider = PushDecider(reconcileSeconds: 60)
    let open = decider.plan(desired: true, now: epoch)
    try decider.record(desired: true, settled: false, generation: #require(open?.generation), at: epoch)
    #expect(decider.pushedDesired == nil)
    #expect(decider.plan(desired: true, now: epoch)?.edge == true)
}

/// A push suspends inside `run()` until `resume()` fires, and signals observers the
/// instant it parks — mirroring the actor-suspension window where a mid-flight
/// `forceReassert` can interleave.
private actor SuspendingPush {
    private var gate: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspended = false

    func run() async {
        await withCheckedContinuation { continuation in
            gate = continuation
            suspended = true
            let waiters = suspensionWaiters
            suspensionWaiters = []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func awaitSuspension() async {
        if suspended {
            return
        }
        await withCheckedContinuation { suspensionWaiters.append($0) }
    }

    func resume() {
        gate?.resume()
        gate = nil
        suspended = false
    }
}

/// Reproduces DaemonCore's push loop against a suspending pusher: `plan` captures
/// the generation before the await, `record` folds the outcome after it.
private actor PushLoop {
    private var decider = PushDecider(reconcileSeconds: 60)
    private let push: SuspendingPush

    init(push: SuspendingPush) {
        self.push = push
    }

    func pushIfNeeded(desired: Bool, settled: Bool, now: Date) async {
        guard let plan = decider.plan(desired: desired, now: now) else { return }
        await push.run()
        decider.record(desired: desired, settled: settled, generation: plan.generation, at: now)
    }

    func forceReassert() {
        decider.forceReassert()
    }

    func wouldRepush(desired: Bool, now: Date) -> Bool {
        decider.plan(desired: desired, now: now) != nil
    }
}

@Test func forcedReassertDuringAnInFlightPushSurvivesTheCompletingRecord() async {
    let push = SuspendingPush()
    let loop = PushLoop(push: push)

    async let inFlight: Void = loop.pushIfNeeded(desired: true, settled: true, now: epoch)
    await push.awaitSuspension()

    // A helper reply-then-crash fires forceReassert() mid-suspension.
    await loop.forceReassert()

    // The push resumes .applied(true); record runs with the now-stale generation.
    await push.resume()
    await inFlight

    // The next evaluate MUST re-push on an edge rather than be suppressed — within
    // the reconcile window, so only the reentrancy guard can produce the re-push.
    let repush = await loop.wouldRepush(desired: true, now: epoch.addingTimeInterval(1))
    #expect(repush)
}

@Test func aSettledPushWithoutAReassertSuppressesTheNextEvaluate() async {
    let push = SuspendingPush()
    let loop = PushLoop(push: push)

    async let inFlight: Void = loop.pushIfNeeded(desired: true, settled: true, now: epoch)
    await push.awaitSuspension()
    await push.resume()
    await inFlight

    let repush = await loop.wouldRepush(desired: true, now: epoch.addingTimeInterval(1))
    #expect(repush == false)
}
