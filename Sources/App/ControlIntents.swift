import AppIntents
import CCVigilAppKit
import CCVigilDaemonKit
import CCVigilShared
import Foundation

/// Thin App Intents over the daemon's CLI socket — the same control path the
/// menu uses (`DaemonCommands`; the app XPC channel is read-only status). Each
/// intent parses its parameters, hands `DaemonCommands.roundTrip` to the pure
/// `ControlIntentLogic`, and returns the resulting phrase as its dialog.
///
/// Shortcuts indexes these on the app's first launch, so the phrases below do
/// not appear in Shortcuts/Siri until cc-vigil has run once.
private func daemonCommands() -> DaemonCommands {
    DaemonCommands(socketPath: SupportPaths(directory: SupportPaths.defaultDirectory).socketPath)
}

struct HoldAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Hold cc-vigil Awake"
    static let description = IntentDescription("Keep the Mac awake for a fixed duration, no oracle required.")

    @Parameter(title: "Duration")
    var duration: Measurement<UnitDuration>?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog: String = switch ControlIntentLogic.requestedSeconds(from: duration, default: ControlIntentLogic.defaultHoldSeconds) {
        case let .seconds(ttlSeconds):
            await ControlIntentLogic.runHold(ttlSeconds: ttlSeconds, send: daemonCommands().roundTrip)
        case let .invalid(message):
            message
        }
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct ReleaseAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Release cc-vigil Hold"
    static let description = IntentDescription("Release the hold created by Hold cc-vigil Awake.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await ControlIntentLogic.runRelease(send: daemonCommands().roundTrip)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct PauseVigilIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause cc-vigil"
    static let description = IntentDescription("Pause all blocking for a fixed duration.")

    @Parameter(title: "Duration")
    var duration: Measurement<UnitDuration>?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog: String = switch ControlIntentLogic.requestedSeconds(from: duration, default: ControlIntentLogic.defaultPauseSeconds) {
        case let .seconds(seconds):
            await ControlIntentLogic.runPause(seconds: seconds, send: daemonCommands().roundTrip)
        case let .invalid(message):
            message
        }
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct ResumeVigilIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume cc-vigil"
    static let description = IntentDescription("Resume blocking after a pause.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await ControlIntentLogic.runResume(send: daemonCommands().roundTrip)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct VigilStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "cc-vigil Status"
    static let description = IntentDescription("Show what the daemon is doing and why.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let summary = await ControlIntentLogic.runStatus(now: Date(), send: daemonCommands().roundTrip)
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct VigilShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HoldAwakeIntent(),
            phrases: [
                "Hold \(.applicationName) awake",
                "Keep \(.applicationName) awake",
            ],
            shortTitle: "Hold Awake",
            systemImageName: "eye.fill"
        )
        AppShortcut(
            intent: ReleaseAwakeIntent(),
            phrases: [
                "Release \(.applicationName) hold",
                "Release \(.applicationName)",
            ],
            shortTitle: "Release Hold",
            systemImageName: "eye.slash"
        )
        AppShortcut(
            intent: PauseVigilIntent(),
            phrases: [
                "Pause \(.applicationName)",
            ],
            shortTitle: "Pause",
            systemImageName: "pause.circle.fill"
        )
        AppShortcut(
            intent: ResumeVigilIntent(),
            phrases: [
                "Resume \(.applicationName)",
            ],
            shortTitle: "Resume",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: VigilStatusIntent(),
            phrases: [
                "\(.applicationName) status",
                "What is \(.applicationName) doing",
            ],
            shortTitle: "Status",
            systemImageName: "eye"
        )
    }
}
