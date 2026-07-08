import CCTranscript
import CCVigilShared
import Foundation

public enum TranscriptProbeError: Error, Equatable {
    case transcript(String)
    case unknownPendingKind(String)

    public var message: String {
        switch self {
        case let .transcript(detail): detail
        case let .unknownPendingKind(kind): "unknown pending kind: \(kind)"
        }
    }
}

public struct TranscriptProber: Sendable {
    public init() {}

    public func probe(path: String) throws -> SessionProbe {
        let activity: SessionActivity
        do {
            activity = try sessionActivity(path: path)
        } catch let error as RustString {
            throw TranscriptProbeError.transcript(error.toString())
        }
        var pending: [CCVigilShared.PendingItem] = []
        for item in activity.pending() {
            let kindString = item.kind().toString()
            guard let kind = PendingKind(rawValue: kindString) else {
                throw TranscriptProbeError.unknownPendingKind(kindString)
            }
            pending.append(CCVigilShared.PendingItem(
                toolUseID: item.tool_use_id().map { $0.toString() },
                name: item.name().toString(),
                kind: kind
            ))
        }
        return SessionProbe(
            sessionPath: path,
            isWaiting: activity.is_waiting(),
            midTool: activity.mid_tool(),
            lastEventEpoch: activity.last_event_epoch(),
            pending: pending
        )
    }
}
