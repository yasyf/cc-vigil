public struct DeadManSwitch: Equatable, Sendable {
    public static let graceSeconds = 60.0

    public private(set) var liveConnections = 0
    public private(set) var generation: UInt64 = 0

    public init() {}

    public mutating func connectionOpened() {
        liveConnections += 1
        generation &+= 1
    }

    public mutating func connectionClosed(whileBlocked: Bool) -> UInt64? {
        precondition(liveConnections > 0, "connectionClosed without a live connection")
        liveConnections -= 1
        generation &+= 1
        guard liveConnections == 0, whileBlocked else { return nil }
        return generation
    }

    public func shouldClear(firedGeneration: UInt64) -> Bool {
        firedGeneration == generation && liveConnections == 0
    }
}
