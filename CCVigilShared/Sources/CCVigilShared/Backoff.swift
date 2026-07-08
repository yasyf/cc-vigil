public struct Backoff: Equatable, Sendable {
    public static let initialSeconds = 1.0
    public static let capSeconds = 30.0

    private var currentSeconds = Backoff.initialSeconds

    public init() {}

    public mutating func next() -> Double {
        let delay = currentSeconds
        currentSeconds = min(currentSeconds * 2, Self.capSeconds)
        return delay
    }

    public mutating func reset() {
        currentSeconds = Self.initialSeconds
    }
}
