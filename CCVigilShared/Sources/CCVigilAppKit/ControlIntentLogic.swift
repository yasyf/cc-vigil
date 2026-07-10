import CCVigilCLIKit
import CCVigilShared
import Foundation

/// Pure parameter-shaping, phrasing, and reply-mapping for the App Intents
/// control surface. The `AppIntent` structs live in the app target and own the
/// AppIntents wiring and the daemon client; this layer stays framework-free and
/// unit-testable. The injected `send` closure is the same seam the CLI's
/// `HoldCommand.perform` uses, so an unreachable daemon is exercised without a
/// socket.
public enum ControlIntentLogic {
    /// The App Intents surface owns one stable hold key: "Hold" adds or refreshes
    /// it (HoldRegistry replaces on a matching key) and "Release" drops it.
    public static let holdKey = "shortcut"
    public static let holdReason = "Shortcuts hold"

    /// TTL for "Hold cc-vigil awake" when the phrase carries no duration.
    public static let defaultHoldSeconds = 3600
    /// Duration for "Pause cc-vigil" when the phrase carries no duration; matches
    /// the menu's "Pause for 1 Hour".
    public static let defaultPauseSeconds = 3600

    /// Dialog for a duration that rounds below one second. The App Intents
    /// surface has no duration string to echo, so it states the rule plainly,
    /// mirroring the CLI's `DurationParseError.nonPositive`. Validating the
    /// rounded value keeps a sub-second-positive pause from collapsing into
    /// `.pause(seconds: 0)`, the Resume sentinel.
    public static let nonPositiveDurationDialog = "The duration must be at least one second."

    public typealias Send = (WireRequest) async throws -> WireResponse

    /// A Shortcuts duration shaped to the daemon's Int seconds, or an invalid
    /// input whose `dialog` the intent surfaces instead of holding.
    public enum RequestedSeconds: Equatable, Sendable {
        case seconds(Int)
        case invalid(String)
    }

    /// Shape a Shortcuts duration to the daemon's Int seconds. A huge or
    /// non-finite value clamps to `Hold.maxTTLSeconds` in Double space, before
    /// the `Int(_:)` conversion that would otherwise trap; a missing duration
    /// uses `fallback`; a non-positive duration is invalid input.
    public static func requestedSeconds(
        from duration: Measurement<UnitDuration>?,
        default fallback: Int
    ) -> RequestedSeconds {
        guard let duration else { return .seconds(fallback) }
        let value = duration.converted(to: .seconds).value
        guard value.isFinite, value <= Double(Hold.maxTTLSeconds) else {
            return .seconds(Hold.maxTTLSeconds)
        }
        let rounded = Int(value.rounded())
        guard rounded > 0 else { return .invalid(nonPositiveDurationDialog) }
        return .seconds(rounded)
    }

    public static func holdDialog(ttlSeconds: Int) -> String {
        "Holding cc-vigil awake for \(Durations.text(forSeconds: ttlSeconds))."
    }

    public static let releaseDialog = "Released the cc-vigil hold."

    public static func pauseDialog(seconds: Int) -> String {
        "Paused cc-vigil for \(Durations.text(forSeconds: seconds))."
    }

    public static let resumeDialog = "Resumed cc-vigil."

    public static func runHold(ttlSeconds: Int, send: Send) async -> String {
        await run(
            .hold(key: holdKey, reason: holdReason, ttlSeconds: ttlSeconds, pid: nil),
            success: holdDialog(ttlSeconds: ttlSeconds),
            send: send
        )
    }

    public static func runRelease(send: Send) async -> String {
        await run(.release(key: holdKey), success: releaseDialog, send: send)
    }

    public static func runPause(seconds: Int, send: Send) async -> String {
        await run(.pause(seconds: seconds), success: pauseDialog(seconds: seconds), send: send)
    }

    public static func runResume(send: Send) async -> String {
        await run(.pause(seconds: 0), success: resumeDialog, send: send)
    }

    public static func runStatus(now: Date, send: Send) async -> String {
        do {
            switch try await send(.status) {
            case let .status(report):
                return StatusRenderer.render(report, now: now)
            case let .error(message):
                return message
            case .ok:
                preconditionFailure("status request returned ok")
            }
        } catch {
            return String(describing: error)
        }
    }

    private static func run(_ request: WireRequest, success: String, send: Send) async -> String {
        do {
            switch try await send(request) {
            case .ok:
                return success
            case let .error(message):
                return message
            case .status:
                preconditionFailure("control op returned a status report")
            }
        } catch {
            return String(describing: error)
        }
    }
}
