import Foundation

public struct Hold: Codable, Equatable, Sendable {
    public static let maxTTLSeconds = 86400

    public let key: String
    public let reason: String
    public let ttlSeconds: Int
    public let createdAt: Date
    public let pid: Int32?

    public var expiresAt: Date {
        createdAt.addingTimeInterval(TimeInterval(ttlSeconds))
    }

    public init(key: String, reason: String, ttlSeconds: Int, createdAt: Date, pid: Int32?) {
        self.key = key
        self.reason = reason
        self.ttlSeconds = min(ttlSeconds, Self.maxTTLSeconds)
        self.createdAt = createdAt
        self.pid = pid
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            from: decoder,
            required: ["createdAt", "key", "reason", "ttlSeconds"],
            optional: ["pid"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ttlSeconds = try container.decode(Int.self, forKey: .ttlSeconds)
        guard 1 ... Self.maxTTLSeconds ~= ttlSeconds else {
            throw DecodingError.dataCorruptedError(
                forKey: .ttlSeconds,
                in: container,
                debugDescription: "ttlSeconds must be in 1...\(Self.maxTTLSeconds)"
            )
        }
        try self.init(
            key: container.decode(String.self, forKey: .key),
            reason: container.decode(String.self, forKey: .reason),
            ttlSeconds: ttlSeconds,
            createdAt: container.decode(Date.self, forKey: .createdAt),
            pid: container.decodeIfPresent(Int32.self, forKey: .pid)
        )
    }
}

public struct HoldRegistry: Equatable, Sendable {
    public private(set) var holds: [Hold]

    public init(holds: [Hold] = []) {
        self.holds = holds
    }

    @discardableResult
    public mutating func add(
        key: String,
        reason: String,
        ttlSeconds: Int,
        pid: Int32?,
        clock: some WallClock
    ) -> Hold {
        let hold = Hold(key: key, reason: reason, ttlSeconds: ttlSeconds, createdAt: clock.now, pid: pid)
        holds.removeAll { $0.key == key }
        holds.append(hold)
        return hold
    }

    @discardableResult
    public mutating func release(key: String) -> Hold? {
        guard let index = holds.firstIndex(where: { $0.key == key }) else { return nil }
        return holds.remove(at: index)
    }

    public func active(clock: some WallClock) -> [Hold] {
        holds.filter { $0.expiresAt > clock.now }
    }

    @discardableResult
    public mutating func prune(clock: some WallClock) -> [Hold] {
        let now = clock.now
        let expired = holds.filter { $0.expiresAt <= now }
        holds.removeAll { $0.expiresAt <= now }
        return expired
    }

    public static func restored(
        from holds: [Hold],
        bootedAt: Date,
        processStart: (Int32) -> Date?
    ) -> HoldRegistry {
        HoldRegistry(holds: holds.filter { hold in
            guard hold.createdAt >= bootedAt else { return false }
            guard let pid = hold.pid else { return true }
            guard let started = processStart(pid) else { return false }
            return started <= hold.createdAt
        })
    }
}
