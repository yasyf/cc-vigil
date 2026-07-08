import Foundation

public enum WireError: Error, Equatable {
    case payloadTooLarge(bytes: Int)
}

public enum WireFrame {
    public static let headerBytes = 4
    public static let maxPayloadBytes = 16 * 1024 * 1024

    public static func encode(payload: Data) throws -> Data {
        guard payload.count <= maxPayloadBytes else {
            throw WireError.payloadTooLarge(bytes: payload.count)
        }
        var frame = Data(capacity: headerBytes + payload.count)
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }

    public static func decode(buffer: Data) throws -> (payload: Data, consumed: Int)? {
        guard buffer.count >= headerBytes else { return nil }
        let length = buffer.prefix(headerBytes).reduce(into: UInt32(0)) { $0 = $0 << 8 | UInt32($1) }
        guard Int(length) <= maxPayloadBytes else {
            throw WireError.payloadTooLarge(bytes: Int(length))
        }
        let total = headerBytes + Int(length)
        guard buffer.count >= total else { return nil }
        let start = buffer.index(buffer.startIndex, offsetBy: headerBytes)
        let end = buffer.index(buffer.startIndex, offsetBy: total)
        return (Data(buffer[start ..< end]), total)
    }
}

public struct NudgePayload: Codable, Equatable, Sendable {
    public let sessionId: String?
    public let hookEvent: String?
    public let notificationKind: String?
    public let claudePid: Int32?

    public init(
        sessionId: String? = nil,
        hookEvent: String? = nil,
        notificationKind: String? = nil,
        claudePid: Int32? = nil
    ) {
        self.sessionId = sessionId
        self.hookEvent = hookEvent
        self.notificationKind = notificationKind
        self.claudePid = claudePid
    }
}

public enum WireRequest: Equatable, Sendable {
    case nudge(NudgePayload)
    case status
    case hold(key: String, reason: String, ttlSeconds: Int, pid: Int32?)
    case release(key: String)
    case pause(seconds: Int)
    case clear
    case ping
}

extension WireRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case operation = "op"
        case sessionId, hookEvent, notificationKind, claudePid, key, reason, ttlSeconds, pid, seconds
    }

    private enum Operation: String, Codable {
        case nudge, status, hold, release, pause, clear, ping
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Operation.self, forKey: .operation) {
        case .nudge:
            self = try .nudge(NudgePayload(
                sessionId: container.decodeIfPresent(String.self, forKey: .sessionId),
                hookEvent: container.decodeIfPresent(String.self, forKey: .hookEvent),
                notificationKind: container.decodeIfPresent(String.self, forKey: .notificationKind),
                claudePid: container.decodeIfPresent(Int32.self, forKey: .claudePid)
            ))
        case .status:
            self = .status
        case .hold:
            self = try .hold(
                key: container.decode(String.self, forKey: .key),
                reason: container.decode(String.self, forKey: .reason),
                ttlSeconds: container.decode(Int.self, forKey: .ttlSeconds),
                pid: container.decodeIfPresent(Int32.self, forKey: .pid)
            )
        case .release:
            self = try .release(key: container.decode(String.self, forKey: .key))
        case .pause:
            self = try .pause(seconds: container.decode(Int.self, forKey: .seconds))
        case .clear:
            self = .clear
        case .ping:
            self = .ping
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .nudge(payload):
            try container.encode(Operation.nudge, forKey: .operation)
            try container.encodeIfPresent(payload.sessionId, forKey: .sessionId)
            try container.encodeIfPresent(payload.hookEvent, forKey: .hookEvent)
            try container.encodeIfPresent(payload.notificationKind, forKey: .notificationKind)
            try container.encodeIfPresent(payload.claudePid, forKey: .claudePid)
        case .status:
            try container.encode(Operation.status, forKey: .operation)
        case let .hold(key, reason, ttlSeconds, pid):
            try container.encode(Operation.hold, forKey: .operation)
            try container.encode(key, forKey: .key)
            try container.encode(reason, forKey: .reason)
            try container.encode(ttlSeconds, forKey: .ttlSeconds)
            try container.encodeIfPresent(pid, forKey: .pid)
        case let .release(key):
            try container.encode(Operation.release, forKey: .operation)
            try container.encode(key, forKey: .key)
        case let .pause(seconds):
            try container.encode(Operation.pause, forKey: .operation)
            try container.encode(seconds, forKey: .seconds)
        case .clear:
            try container.encode(Operation.clear, forKey: .operation)
        case .ping:
            try container.encode(Operation.ping, forKey: .operation)
        }
    }
}

public enum HelperLink: String, Codable, Equatable, Sendable {
    case dryRun = "dry-run"
    case unknown
    case reachable
    case unreachable
}

public struct StatusReport: Codable, Equatable, Sendable {
    public let shouldBlock: Bool
    public let blockApplied: Bool
    public let helper: HelperLink
    public let activeSessions: [ActiveSession]
    public let holds: [Hold]
    public let latchedCutouts: [CutoutKind]
    public let pausedUntil: Date?

    public init(
        shouldBlock: Bool,
        blockApplied: Bool,
        helper: HelperLink,
        activeSessions: [ActiveSession],
        holds: [Hold],
        latchedCutouts: [CutoutKind],
        pausedUntil: Date?
    ) {
        self.shouldBlock = shouldBlock
        self.blockApplied = blockApplied
        self.helper = helper
        self.activeSessions = activeSessions
        self.holds = holds
        self.latchedCutouts = latchedCutouts
        self.pausedUntil = pausedUntil
    }
}

public enum WireResponse: Equatable, Sendable {
    case ok
    case status(StatusReport)
    case error(message: String)
}

extension WireResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case result, status, message
    }

    private enum Result: String, Codable {
        case ok, status, error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Result.self, forKey: .result) {
        case .ok:
            self = .ok
        case .status:
            self = try .status(container.decode(StatusReport.self, forKey: .status))
        case .error:
            self = try .error(message: container.decode(String.self, forKey: .message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ok:
            try container.encode(Result.ok, forKey: .result)
        case let .status(report):
            try container.encode(Result.status, forKey: .result)
            try container.encode(report, forKey: .status)
        case let .error(message):
            try container.encode(Result.error, forKey: .result)
            try container.encode(message, forKey: .message)
        }
    }
}

public enum WireCodec {
    public static func encodeFrame(_ value: some Encodable) throws -> Data {
        try WireFrame.encode(payload: encodePayload(value))
    }

    public static func decodeFrame<T: Decodable>(
        _ type: T.Type,
        from buffer: Data
    ) throws -> (value: T, consumed: Int)? {
        guard let (payload, consumed) = try WireFrame.decode(buffer: buffer) else { return nil }
        return try (decodePayload(type, from: payload), consumed)
    }

    public static func encodePayload(_ value: some Encodable) throws -> Data {
        try makeEncoder().encode(value)
    }

    public static func decodePayload<T: Decodable>(_ type: T.Type, from payload: Data) throws -> T {
        try makeDecoder().decode(type, from: payload)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
