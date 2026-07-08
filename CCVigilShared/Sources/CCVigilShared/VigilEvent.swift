import Foundation

public enum VigilEvent: Equatable, Sendable {
    case daemonStarted(version: String, dryRun: Bool)
    case daemonStopped
    case blockEdge(blocked: Bool, applied: Bool, decision: BlockDecision)
    case cutoutLatched(CutoutKind)
    case cutoutCleared(CutoutKind)
    case lidChanged(closed: Bool)
    case holdAdded(Hold)
    case holdReleased(key: String)
    case holdsExpired(keys: [String])
    case probeFailed(path: String, message: String)
    case paused(until: Date)
    case resumed
    case wake
}

public struct EventRecord: Equatable, Sendable {
    public let at: Date
    public let event: VigilEvent

    public init(at: Date, event: VigilEvent) {
        self.at = at
        self.event = event
    }
}

extension EventRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case at, event, version, dryRun, blocked, applied, decision, kind, closed,
             hold, key, keys, path, message, until
    }

    private enum Kind: String, Codable {
        case daemonStarted = "daemon-started"
        case daemonStopped = "daemon-stopped"
        case blockEdge = "block-edge"
        case cutoutLatched = "cutout-latched"
        case cutoutCleared = "cutout-cleared"
        case lidChanged = "lid"
        case holdAdded = "hold-added"
        case holdReleased = "hold-released"
        case holdsExpired = "holds-expired"
        case probeFailed = "probe-failed"
        case paused, resumed, wake
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let at = try container.decode(Date.self, forKey: .at)
        let event: VigilEvent = switch try container.decode(Kind.self, forKey: .event) {
        case .daemonStarted:
            try .daemonStarted(
                version: container.decode(String.self, forKey: .version),
                dryRun: container.decode(Bool.self, forKey: .dryRun)
            )
        case .daemonStopped:
            .daemonStopped
        case .blockEdge:
            try .blockEdge(
                blocked: container.decode(Bool.self, forKey: .blocked),
                applied: container.decode(Bool.self, forKey: .applied),
                decision: container.decode(BlockDecision.self, forKey: .decision)
            )
        case .cutoutLatched:
            try .cutoutLatched(container.decode(CutoutKind.self, forKey: .kind))
        case .cutoutCleared:
            try .cutoutCleared(container.decode(CutoutKind.self, forKey: .kind))
        case .lidChanged:
            try .lidChanged(closed: container.decode(Bool.self, forKey: .closed))
        case .holdAdded:
            try .holdAdded(container.decode(Hold.self, forKey: .hold))
        case .holdReleased:
            try .holdReleased(key: container.decode(String.self, forKey: .key))
        case .holdsExpired:
            try .holdsExpired(keys: container.decode([String].self, forKey: .keys))
        case .probeFailed:
            try .probeFailed(
                path: container.decode(String.self, forKey: .path),
                message: container.decode(String.self, forKey: .message)
            )
        case .paused:
            try .paused(until: container.decode(Date.self, forKey: .until))
        case .resumed:
            .resumed
        case .wake:
            .wake
        }
        self.init(at: at, event: event)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(at, forKey: .at)
        switch event {
        case let .daemonStarted(version, dryRun):
            try container.encode(Kind.daemonStarted, forKey: .event)
            try container.encode(version, forKey: .version)
            try container.encode(dryRun, forKey: .dryRun)
        case .daemonStopped:
            try container.encode(Kind.daemonStopped, forKey: .event)
        case let .blockEdge(blocked, applied, decision):
            try container.encode(Kind.blockEdge, forKey: .event)
            try container.encode(blocked, forKey: .blocked)
            try container.encode(applied, forKey: .applied)
            try container.encode(decision, forKey: .decision)
        case let .cutoutLatched(kind):
            try container.encode(Kind.cutoutLatched, forKey: .event)
            try container.encode(kind, forKey: .kind)
        case let .cutoutCleared(kind):
            try container.encode(Kind.cutoutCleared, forKey: .event)
            try container.encode(kind, forKey: .kind)
        case let .lidChanged(closed):
            try container.encode(Kind.lidChanged, forKey: .event)
            try container.encode(closed, forKey: .closed)
        case let .holdAdded(hold):
            try container.encode(Kind.holdAdded, forKey: .event)
            try container.encode(hold, forKey: .hold)
        case let .holdReleased(key):
            try container.encode(Kind.holdReleased, forKey: .event)
            try container.encode(key, forKey: .key)
        case let .holdsExpired(keys):
            try container.encode(Kind.holdsExpired, forKey: .event)
            try container.encode(keys, forKey: .keys)
        case let .probeFailed(path, message):
            try container.encode(Kind.probeFailed, forKey: .event)
            try container.encode(path, forKey: .path)
            try container.encode(message, forKey: .message)
        case let .paused(until):
            try container.encode(Kind.paused, forKey: .event)
            try container.encode(until, forKey: .until)
        case .resumed:
            try container.encode(Kind.resumed, forKey: .event)
        case .wake:
            try container.encode(Kind.wake, forKey: .event)
        }
    }
}
