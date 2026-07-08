import Foundation

public protocol WallClock: Sendable {
    var now: Date { get }
}

public struct SystemClock: WallClock {
    public init() {}

    public var now: Date {
        Date()
    }
}
