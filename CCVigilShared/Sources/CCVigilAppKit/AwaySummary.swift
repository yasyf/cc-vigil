import CCVigilCLIKit
import CCVigilRuntime
import CCVigilShared
import Foundation

public struct AwaySummary: Equatable, Sendable {
    public let blockCount: Int
    public let awakeSeconds: Int
    public let cutouts: [CutoutKind]

    public init(blockCount: Int, awakeSeconds: Int, cutouts: [CutoutKind]) {
        self.blockCount = blockCount
        self.awakeSeconds = awakeSeconds
        self.cutouts = cutouts
    }

    public var lines: [String] {
        var lines: [String] = []
        if blockCount > 0 {
            let blocks = blockCount == 1 ? "1 block" : "\(blockCount) blocks"
            lines.append("kept awake \(Durations.text(forSeconds: awakeSeconds)) across \(blocks)")
        }
        if !cutouts.isEmpty {
            lines.append("cutouts latched: \(cutouts.map(\.rawValue).joined(separator: ", "))")
        }
        return lines
    }
}

public enum AwayDigest {
    public static func decodeRecords(fromJSONL data: Data) throws -> [EventRecord] {
        try EventLog.decodeRecords(fromJSONL: data)
    }

    public static func summarize(records: [EventRecord], since: Date, now: Date) -> AwaySummary {
        var blockCount = 0
        var awakeSeconds = 0.0
        for segment in blockedSegments(in: records, now: now) {
            let start = max(segment.start, since)
            let end = min(segment.end, now)
            guard end > start else { continue }
            blockCount += 1
            awakeSeconds += end.timeIntervalSince(start)
        }
        let cutouts = records
            .filter { $0.at > since && $0.at <= now }
            .compactMap { record in
                if case let .cutoutLatched(kind) = record.event {
                    kind
                } else {
                    nil
                }
            }
        return AwaySummary(
            blockCount: blockCount,
            awakeSeconds: Int(awakeSeconds.rounded()),
            cutouts: cutouts.reduce(into: []) { unique, kind in
                if !unique.contains(kind) {
                    unique.append(kind)
                }
            }
        )
    }

    private static func blockedSegments(
        in records: [EventRecord],
        now: Date
    ) -> [(start: Date, end: Date)] {
        var segments: [(start: Date, end: Date)] = []
        var openStart: Date?
        for record in records where record.at <= now {
            switch record.event {
            case let .blockEdge(blocked, _, _, _) where blocked:
                openStart = openStart ?? record.at
            // A block-off edge or a daemon stop (or the restart after a crash)
            // ends any open block.
            case .blockEdge, .daemonStarted, .daemonStopped:
                if let start = openStart {
                    segments.append((start, record.at))
                    openStart = nil
                }
            case .cutoutLatched, .cutoutCleared, .lidChanged, .holdAdded, .holdReleased,
                 .holdsExpired, .probeFailed, .paused, .resumed, .wake:
                break
            }
        }
        if let start = openStart {
            segments.append((start, now))
        }
        return segments
    }
}
