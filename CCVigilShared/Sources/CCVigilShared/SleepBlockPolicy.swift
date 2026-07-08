public enum SleepBlockAction: Equatable, Sendable {
    case createAssertion
    case releaseAssertion
    case setPmsetDisableSleep(Bool)
}

public enum SleepBlockOutcome: Equatable, Sendable {
    case assertionCreated(success: Bool)
    case assertionReleased
    case pmsetCompleted(disableSleep: Bool, success: Bool)
}

public enum PmsetApplied: Equatable, Sendable {
    case unknown
    case disableSleep(Bool)

    public var knownDisableSleep: Bool? {
        switch self {
        case .unknown: nil
        case let .disableSleep(value): value
        }
    }
}

public struct SleepBlockState: Codable, Equatable, Sendable {
    public let desired: Bool
    public let assertionHeld: Bool
    public let pmsetDisableSleep: Bool?

    public var isSettled: Bool {
        desired
            ? assertionHeld && pmsetDisableSleep == true
            : !assertionHeld && pmsetDisableSleep == false
    }

    public init(desired: Bool, assertionHeld: Bool, pmsetDisableSleep: Bool?) {
        self.desired = desired
        self.assertionHeld = assertionHeld
        self.pmsetDisableSleep = pmsetDisableSleep
    }
}

public struct SleepBlockPolicy: Equatable, Sendable {
    public private(set) var desired = false
    public private(set) var assertionHeld = false
    public private(set) var pmset = PmsetApplied.unknown

    public init() {}

    public var needsClear: Bool {
        pmset == .unknown
    }

    public var isBlocking: Bool {
        desired && assertionHeld && pmset == .disableSleep(true)
    }

    public var state: SleepBlockState {
        SleepBlockState(
            desired: desired,
            assertionHeld: assertionHeld,
            pmsetDisableSleep: pmset.knownDisableSleep
        )
    }

    public mutating func set(_ blocked: Bool) -> [SleepBlockAction] {
        desired = blocked
        return blocked
            ? [.createAssertion, .setPmsetDisableSleep(true)]
            : [.releaseAssertion, .setPmsetDisableSleep(false)]
    }

    public mutating func record(_ outcome: SleepBlockOutcome) {
        switch outcome {
        case let .assertionCreated(success):
            assertionHeld = success
        case .assertionReleased:
            assertionHeld = false
        case let .pmsetCompleted(disableSleep, success):
            pmset = success ? .disableSleep(disableSleep) : .unknown
        }
    }
}
