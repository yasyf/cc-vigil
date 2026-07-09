import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    public let holds: [Hold]
    public let pausedUntil: Date?
    public let registeredRoots: [String]

    public init(holds: [Hold], pausedUntil: Date?, registeredRoots: [String] = []) {
        self.holds = holds
        self.pausedUntil = pausedUntil
        self.registeredRoots = registeredRoots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holds = try container.decode([Hold].self, forKey: .holds)
        pausedUntil = try container.decodeIfPresent(Date.self, forKey: .pausedUntil)
        registeredRoots = try container.decodeIfPresent([String].self, forKey: .registeredRoots) ?? []
    }
}
