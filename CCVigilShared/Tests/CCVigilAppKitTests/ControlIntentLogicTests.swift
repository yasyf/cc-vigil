import CCVigilAppKit
import CCVigilCLIKit
import CCVigilShared
import CCVigilTransport
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_767_000_000)

private func report() -> StatusReport {
    StatusReport(
        shouldBlock: false,
        blockApplied: false,
        helper: .reachable,
        activeSessions: [],
        holds: [],
        latchedCutouts: [],
        pausedUntil: nil
    )
}

@Test(arguments: [
    (Measurement<UnitDuration>(value: 60, unit: .seconds), ControlIntentLogic.RequestedSeconds.seconds(60)),
    (Measurement<UnitDuration>(value: 5, unit: .minutes), .seconds(300)),
    (Measurement<UnitDuration>(value: Double(Hold.maxTTLSeconds), unit: .seconds), .seconds(Hold.maxTTLSeconds)),
    (Measurement<UnitDuration>(value: Double(Hold.maxTTLSeconds) + 1, unit: .seconds), .seconds(Hold.maxTTLSeconds)),
    (Measurement<UnitDuration>(value: 1_000_000, unit: .seconds), .seconds(Hold.maxTTLSeconds)),
    (Measurement<UnitDuration>(value: 1e300, unit: .seconds), .seconds(Hold.maxTTLSeconds)),
    (Measurement<UnitDuration>(value: .infinity, unit: .seconds), .seconds(Hold.maxTTLSeconds)),
])
func requestedSecondsClampsToTheHoldCeiling(
    duration: Measurement<UnitDuration>,
    expected: ControlIntentLogic.RequestedSeconds
) {
    #expect(ControlIntentLogic.requestedSeconds(from: duration, default: 3600) == expected)
}

@Test(arguments: [
    Measurement<UnitDuration>(value: 0, unit: .seconds),
    Measurement<UnitDuration>(value: -5, unit: .seconds),
    Measurement<UnitDuration>(value: -30, unit: .minutes),
    Measurement<UnitDuration>(value: 0.4, unit: .seconds),
])
func requestedSecondsRejectsDurationsBelowOneSecond(duration: Measurement<UnitDuration>) {
    #expect(
        ControlIntentLogic.requestedSeconds(from: duration, default: 3600)
            == .invalid(ControlIntentLogic.nonPositiveDurationDialog)
    )
}

@Test func requestedSecondsRoundsHalfASecondUpToOne() {
    #expect(
        ControlIntentLogic.requestedSeconds(
            from: Measurement<UnitDuration>(value: 0.5, unit: .seconds), default: 3600
        ) == .seconds(1)
    )
}

@Test func requestedSecondsUsesTheFallbackWhenNoDurationIsGiven() {
    #expect(ControlIntentLogic.requestedSeconds(from: nil, default: 3600) == .seconds(3600))
}

@Test(arguments: [
    (1800, "Holding cc-vigil awake for 30m."),
    (7200, "Holding cc-vigil awake for 2h."),
])
func holdDialogFormatsTheDuration(ttlSeconds: Int, expected: String) {
    #expect(ControlIntentLogic.holdDialog(ttlSeconds: ttlSeconds) == expected)
}

@Test func pauseDialogFormatsTheDuration() {
    #expect(ControlIntentLogic.pauseDialog(seconds: 3600) == "Paused cc-vigil for 1h.")
}

@Test func holdSendsTheStableKeyAndReturnsTheSuccessPhrase() async {
    var captured: WireRequest?
    let dialog = await ControlIntentLogic.runHold(ttlSeconds: 1800) { request in
        captured = request
        return .ok
    }
    #expect(captured == .hold(key: "shortcut", reason: "Shortcuts hold", ttlSeconds: 1800, pid: nil))
    #expect(dialog == "Holding cc-vigil awake for 30m.")
}

@Test func releaseSendsTheStableKey() async {
    var captured: WireRequest?
    let dialog = await ControlIntentLogic.runRelease { request in
        captured = request
        return .ok
    }
    #expect(captured == .release(key: "shortcut"))
    #expect(dialog == "Released the cc-vigil hold.")
}

@Test func pauseSendsTheRequestedSeconds() async {
    var captured: WireRequest?
    let dialog = await ControlIntentLogic.runPause(seconds: 3600) { request in
        captured = request
        return .ok
    }
    #expect(captured == .pause(seconds: 3600))
    #expect(dialog == "Paused cc-vigil for 1h.")
}

@Test func resumeSendsPauseZero() async {
    var captured: WireRequest?
    let dialog = await ControlIntentLogic.runResume { request in
        captured = request
        return .ok
    }
    #expect(captured == .pause(seconds: 0))
    #expect(dialog == "Resumed cc-vigil.")
}

@Test func aDaemonErrorSurfacesItsMessage() async {
    let dialog = await ControlIntentLogic.runRelease { _ in
        .error(message: "no hold with key shortcut")
    }
    #expect(dialog == "no hold with key shortcut")
}

@Test func anUnreachableDaemonSurfacesTheClientError() async {
    let dialog = await ControlIntentLogic.runHold(ttlSeconds: 60) { _ in
        throw DaemonClientError.transport("connect errno 2")
    }
    #expect(dialog == "daemon session failed: connect errno 2")
}

@Test func statusRendersTheHumanSummary() async {
    var captured: WireRequest?
    let dialog = await ControlIntentLogic.runStatus(now: now) { request in
        captured = request
        return .status(report())
    }
    #expect(captured == .status)
    #expect(dialog == StatusRenderer.render(report(), now: now))
    #expect(dialog.contains("blocking: no"))
}

@Test func statusOnAnUnreachableDaemonSurfacesTheClientError() async {
    let dialog = await ControlIntentLogic.runStatus(now: now) { _ in
        throw DaemonClientError.transport("connect errno 61")
    }
    #expect(dialog == "daemon session failed: connect errno 61")
}
