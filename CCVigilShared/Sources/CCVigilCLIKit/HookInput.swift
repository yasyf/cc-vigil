import CCVigilShared
import Foundation

public enum HookInputError: Error, Equatable, CustomStringConvertible {
    case notJSON
    case notObject

    public var description: String {
        switch self {
        case .notJSON: "stdin is not JSON"
        case .notObject: "hook JSON root is not an object"
        }
    }
}

public enum HookInput {
    public static func nudgePayload(fromHookJSON data: Data, claudePid: Int32?) throws -> NudgePayload {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
            throw HookInputError.notJSON
        }
        guard let object = parsed as? [String: Any] else {
            throw HookInputError.notObject
        }
        return NudgePayload(
            sessionId: object["session_id"] as? String,
            hookEvent: object["hook_event_name"] as? String,
            notificationKind: object["notification_type"] as? String,
            claudePid: claudePid
        )
    }
}
