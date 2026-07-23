import Foundation

/// A user-facing sleep-protection edge the daemon composed from its own status
/// stream: a block releasing into a truly-idle Mac, or a cutout latching
/// mid-work. The monotonic `id` lets the App layer replay each alert exactly
/// once across reconnects; `payload` carries only what the toast needs.
public struct SleepAlert: Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case released
        case cutoutLatched
    }

    public enum Payload: Equatable, Sendable {
        case released(sessions: Int, holds: Int)
        case cutoutLatched(kinds: [CutoutKind])
    }

    public let id: Int64
    public let atEpoch: Int64
    public let payload: Payload

    public init(id: Int64, atEpoch: Int64, payload: Payload) {
        self.id = id
        self.atEpoch = atEpoch
        self.payload = payload
    }

    public var kind: Kind {
        switch payload {
        case .released: .released
        case .cutoutLatched: .cutoutLatched
        }
    }
}

extension SleepAlert: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, atEpoch, sessions, holds, kinds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        atEpoch = try container.decode(Int64.self, forKey: .atEpoch)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .released:
            try requireExactKeys(
                from: decoder,
                required: ["atEpoch", "holds", "id", "kind", "sessions"]
            )
            payload = try .released(
                sessions: container.decode(Int.self, forKey: .sessions),
                holds: container.decode(Int.self, forKey: .holds)
            )
        case .cutoutLatched:
            try requireExactKeys(
                from: decoder,
                required: ["atEpoch", "id", "kind", "kinds"]
            )
            payload = try .cutoutLatched(kinds: container.decode([CutoutKind].self, forKey: .kinds))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(atEpoch, forKey: .atEpoch)
        try container.encode(kind, forKey: .kind)
        switch payload {
        case let .released(sessions, holds):
            try container.encode(sessions, forKey: .sessions)
            try container.encode(holds, forKey: .holds)
        case let .cutoutLatched(kinds):
            try container.encode(kinds, forKey: .kinds)
        }
    }
}
