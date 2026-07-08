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
        let summary: SessionActivitySummary
        do {
            summary = try sessionActivity(path: path)
        } catch let error as RustString {
            throw TranscriptProbeError.transcript(error.toString())
        }
        var pending: [CCVigilShared.PendingItem] = []
        for item in summary.pending {
            guard let kind = PendingKind(rawValue: item.kind) else {
                throw TranscriptProbeError.unknownPendingKind(item.kind)
            }
            pending.append(CCVigilShared.PendingItem(
                toolUseID: item.toolUseId,
                name: item.name,
                kind: kind
            ))
        }
        return SessionProbe(
            sessionPath: path,
            isWaiting: summary.isWaiting,
            midTool: summary.midTool,
            lastEventEpoch: summary.lastEventEpoch,
            pending: pending
        )
    }
}
