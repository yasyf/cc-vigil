import CCVigilAppKit
import CCVigilCLIKit
import CCVigilShared
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
    (60, 60),
    (0, 1),
    (-5, 1),
    (86400, 86400),
    (86401, 86400),
    (1_000_000, 86400),
])
func clampsRequestedDurationToTheHoldCeiling(requested: Int, expected: Int) {
    #expect(ControlIntentLogic.clampedSeconds(requested) == expected)
    #expect(expected <= Hold.maxTTLSeconds)
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
        throw SocketClientError.connectFailed(errno: 2)
    }
    #expect(dialog == "cannot connect to the daemon socket (errno 2); is CCVigilDaemon running?")
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
        throw SocketClientError.connectFailed(errno: 61)
    }
    #expect(dialog.contains("is CCVigilDaemon running?"))
}
