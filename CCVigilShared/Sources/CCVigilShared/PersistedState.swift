import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    public let holds: [Hold]
    public let pausedUntil: Date?

    public init(holds: [Hold], pausedUntil: Date?) {
        self.holds = holds
        self.pausedUntil = pausedUntil
    }
}
