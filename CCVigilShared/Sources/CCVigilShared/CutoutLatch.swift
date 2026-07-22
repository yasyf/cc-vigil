public enum CutoutKind: String, Codable, Equatable, Sendable, CaseIterable {
    case battery
    case thermal
    case lowPower = "low-power"

    public var rejectionReason: String {
        "cutout-\(rawValue)"
    }
}

public struct PowerSample: Equatable, Sendable {
    public let onBattery: Bool
    public let batteryPercent: Int
    public let thermalCelsius: Double?
    public let lidClosed: Bool
    public let blocking: Bool
    public let lowPowerEnabled: Bool

    public init(
        onBattery: Bool,
        batteryPercent: Int,
        thermalCelsius: Double?,
        lidClosed: Bool,
        blocking: Bool,
        lowPowerEnabled: Bool
    ) {
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.thermalCelsius = thermalCelsius
        self.lidClosed = lidClosed
        self.blocking = blocking
        self.lowPowerEnabled = lowPowerEnabled
    }
}

public enum CutoutEvent: Equatable, Sendable {
    case latched(CutoutKind)
    case cleared(CutoutKind)
}

public struct CutoutLatch: Equatable, Sendable {
    public static let batteryHysteresisPercent = 5
    public static let thermalHysteresisCelsius = 5.0

    public private(set) var latched: Set<CutoutKind> = []

    private let batteryFloorPercent: Int
    private let thermalCutoutCelsius: Double

    public init(config: VigilConfig) {
        batteryFloorPercent = config.batteryFloorPercent
        thermalCutoutCelsius = config.thermalCutoutCelsius
    }

    public var rejectsAcquire: Bool {
        !latched.isEmpty
    }

    public var rejectionReasons: [String] {
        latched.map(\.rejectionReason).sorted()
    }

    public mutating func update(with sample: PowerSample) -> [CutoutEvent] {
        updateBattery(sample) + updateThermal(sample) + updateLowPower(sample)
    }

    private mutating func updateBattery(_ sample: PowerSample) -> [CutoutEvent] {
        if latched.contains(.battery) {
            let recovered = sample.batteryPercent >= batteryFloorPercent + Self.batteryHysteresisPercent
            guard !sample.onBattery || recovered else { return [] }
            latched.remove(.battery)
            return [.cleared(.battery)]
        }
        guard sample.onBattery, sample.batteryPercent < batteryFloorPercent else { return [] }
        latched.insert(.battery)
        return [.latched(.battery)]
    }

    private mutating func updateThermal(_ sample: PowerSample) -> [CutoutEvent] {
        if latched.contains(.thermal) {
            let cooled = sample.thermalCelsius
                .map { $0 <= thermalCutoutCelsius - Self.thermalHysteresisCelsius } ?? false
            guard !sample.lidClosed || cooled else { return [] }
            latched.remove(.thermal)
            return [.cleared(.thermal)]
        }
        guard sample.lidClosed, sample.blocking,
              let celsius = sample.thermalCelsius, celsius >= thermalCutoutCelsius
        else { return [] }
        latched.insert(.thermal)
        return [.latched(.thermal)]
    }

    private mutating func updateLowPower(_ sample: PowerSample) -> [CutoutEvent] {
        if latched.contains(.lowPower) {
            guard !sample.lowPowerEnabled else { return [] }
            latched.remove(.lowPower)
            return [.cleared(.lowPower)]
        }
        guard sample.lowPowerEnabled else { return [] }
        latched.insert(.lowPower)
        return [.latched(.lowPower)]
    }
}
