import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    public let holds: [Hold]
    public let pausedUntil: Date?
    public let registeredRoots: [String]
    public let nextAlertId: Int64
    public let recentAlerts: [SleepAlert]
    public let alertedCutouts: Set<CutoutKind>

    public init(
        holds: [Hold],
        pausedUntil: Date?,
        registeredRoots: [String] = [],
        nextAlertId: Int64 = 1,
        recentAlerts: [SleepAlert] = [],
        alertedCutouts: Set<CutoutKind> = []
    ) {
        self.holds = holds
        self.pausedUntil = pausedUntil
        self.registeredRoots = registeredRoots
        self.nextAlertId = nextAlertId
        self.recentAlerts = recentAlerts
        self.alertedCutouts = alertedCutouts
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            from: decoder,
            required: ["alertedCutouts", "holds", "nextAlertId", "recentAlerts", "registeredRoots"],
            optional: ["pausedUntil"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holds = try container.decode([Hold].self, forKey: .holds)
        pausedUntil = try container.decodeIfPresent(Date.self, forKey: .pausedUntil)
        registeredRoots = try container.decode([String].self, forKey: .registeredRoots)
        nextAlertId = try container.decode(Int64.self, forKey: .nextAlertId)
        recentAlerts = try container.decode([SleepAlert].self, forKey: .recentAlerts)
        alertedCutouts = try container.decode(Set<CutoutKind>.self, forKey: .alertedCutouts)
    }
}
