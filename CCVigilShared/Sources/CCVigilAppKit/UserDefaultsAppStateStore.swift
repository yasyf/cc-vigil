import CCVigilShared
import Foundation
import os

public enum AppStateSchemaV1 {
    public static let identity = "dev.yasyf.cc-vigil.app-state"
    public static let storageKey = "dev.yasyf.cc-vigil.app-state.v1"
    public static let fingerprint = ExactPersistedJSONV1.fingerprint(
        identity: identity,
        descriptor: [
            "payload{firstRunCompleted:bool,lastMenuOpenedAt:null|epoch-seconds,",
            "lastSeenSleepAlertId:null|int64,repairConsecutiveFailures:int}",
        ].joined()
    )
}

public enum AppStateStoreError: Error, Equatable {
    case invalidStoredType(String)
    case invalidRepairFailureCount(Int)
    case invalidAlertWatermark(Int64)
}

public final class UserDefaultsAppStateStore: AlertWatermarkStore, RepairFailureCountStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let state: OSAllocatedUnfairLock<AppStateV1>

    public init(defaults: UserDefaults = .standard) throws {
        self.defaults = defaults
        let initial: AppStateV1
        if let stored = defaults.object(forKey: AppStateSchemaV1.storageKey) {
            guard let data = stored as? Data else {
                throw AppStateStoreError.invalidStoredType(String(describing: type(of: stored)))
            }
            initial = try ExactPersistedJSONV1.decode(
                AppStateV1.self,
                from: data,
                identity: AppStateSchemaV1.identity,
                fingerprint: AppStateSchemaV1.fingerprint
            )
        } else {
            initial = .fresh
        }
        state = OSAllocatedUnfairLock(initialState: initial)
    }

    public var firstRunCompleted: Bool {
        state.withLock(\.firstRunCompleted)
    }

    public var lastMenuOpenedAt: Date? {
        state.withLock(\.lastMenuOpenedAt)
    }

    public var consecutiveFailures: Int {
        state.withLock(\.repairConsecutiveFailures)
    }

    public var lastSeenAlertId: Int64? {
        state.withLock(\.lastSeenSleepAlertId)
    }

    public func recordFirstRunCompleted(_ completed: Bool) {
        update { $0.firstRunCompleted = completed }
    }

    public func recordMenuOpened(at date: Date) {
        update { $0.lastMenuOpenedAt = date }
    }

    public func record(_ count: Int) {
        guard count >= 0 else { preconditionFailure("repair failure count must be nonnegative") }
        update { $0.repairConsecutiveFailures = count }
    }

    public func recordSeen(_ id: Int64) {
        guard id > 0 else { preconditionFailure("alert watermark must be positive") }
        update { value in
            if let current = value.lastSeenSleepAlertId, id < current {
                preconditionFailure("alert watermark must not move backward")
            }
            value.lastSeenSleepAlertId = id
        }
    }

    private func update(_ body: @Sendable (inout AppStateV1) -> Void) {
        state.withLock { value in
            body(&value)
            do {
                let data = try ExactPersistedJSONV1.encode(
                    value,
                    identity: AppStateSchemaV1.identity,
                    fingerprint: AppStateSchemaV1.fingerprint
                )
                defaults.set(data, forKey: AppStateSchemaV1.storageKey)
            } catch {
                preconditionFailure("encode app state: \(error)")
            }
        }
    }
}

private struct AppStateV1: Codable {
    private enum CodingKeys: String, CodingKey {
        case firstRunCompleted, lastMenuOpenedAt, lastSeenSleepAlertId, repairConsecutiveFailures
    }

    static let fresh = AppStateV1(
        firstRunCompleted: false,
        lastMenuOpenedAt: nil,
        lastSeenSleepAlertId: nil,
        repairConsecutiveFailures: 0
    )

    var firstRunCompleted: Bool
    var lastMenuOpenedAt: Date?
    var lastSeenSleepAlertId: Int64?
    var repairConsecutiveFailures: Int

    init(
        firstRunCompleted: Bool,
        lastMenuOpenedAt: Date?,
        lastSeenSleepAlertId: Int64?,
        repairConsecutiveFailures: Int
    ) {
        self.firstRunCompleted = firstRunCompleted
        self.lastMenuOpenedAt = lastMenuOpenedAt
        self.lastSeenSleepAlertId = lastSeenSleepAlertId
        self.repairConsecutiveFailures = repairConsecutiveFailures
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(
            from: decoder,
            required: [
                "firstRunCompleted", "lastMenuOpenedAt", "lastSeenSleepAlertId", "repairConsecutiveFailures",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstRunCompleted = try container.decode(Bool.self, forKey: .firstRunCompleted)
        lastMenuOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastMenuOpenedAt)
        lastSeenSleepAlertId = try container.decodeIfPresent(Int64.self, forKey: .lastSeenSleepAlertId)
        repairConsecutiveFailures = try container.decode(Int.self, forKey: .repairConsecutiveFailures)
        guard repairConsecutiveFailures >= 0 else {
            throw AppStateStoreError.invalidRepairFailureCount(repairConsecutiveFailures)
        }
        if let lastSeenSleepAlertId, lastSeenSleepAlertId <= 0 {
            throw AppStateStoreError.invalidAlertWatermark(lastSeenSleepAlertId)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(firstRunCompleted, forKey: .firstRunCompleted)
        if let lastMenuOpenedAt {
            try container.encode(lastMenuOpenedAt, forKey: .lastMenuOpenedAt)
        } else {
            try container.encodeNil(forKey: .lastMenuOpenedAt)
        }
        if let lastSeenSleepAlertId {
            try container.encode(lastSeenSleepAlertId, forKey: .lastSeenSleepAlertId)
        } else {
            try container.encodeNil(forKey: .lastSeenSleepAlertId)
        }
        try container.encode(repairConsecutiveFailures, forKey: .repairConsecutiveFailures)
    }
}
