import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    public let holds: [Hold]
    public let pausedUntil: Date?
    public let registeredRoots: [String]
    public let nextAlertId: Int64
    public let recentAlerts: [SleepAlert]

    public init(
        holds: [Hold],
        pausedUntil: Date?,
        registeredRoots: [String] = [],
        nextAlertId: Int64 = 1,
        recentAlerts: [SleepAlert] = []
    ) {
        self.holds = holds
        self.pausedUntil = pausedUntil
        self.registeredRoots = registeredRoots
        self.nextAlertId = nextAlertId
        self.recentAlerts = recentAlerts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holds = try container.decode([Hold].self, forKey: .holds)
        pausedUntil = try container.decodeIfPresent(Date.self, forKey: .pausedUntil)
        registeredRoots = try container.decodeIfPresent([String].self, forKey: .registeredRoots) ?? []
        nextAlertId = try container.decodeIfPresent(Int64.self, forKey: .nextAlertId) ?? 1
        recentAlerts = try container.decodeIfPresent([SleepAlert].self, forKey: .recentAlerts) ?? []
    }
}
