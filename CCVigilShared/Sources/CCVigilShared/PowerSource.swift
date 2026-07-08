public struct BatteryReading: Equatable, Sendable {
    public let onBattery: Bool
    public let percent: Int

    public init(onBattery: Bool, percent: Int) {
        self.onBattery = onBattery
        self.percent = percent
    }
}

public enum BatterySourceParser {
    public static let typeKey = "Type"
    public static let internalBatteryType = "InternalBattery"
    public static let stateKey = "Power Source State"
    public static let batteryPowerState = "Battery Power"
    public static let currentCapacityKey = "Current Capacity"
    public static let maxCapacityKey = "Max Capacity"

    public static func reading(fromSources sources: [[String: Any]]) -> BatteryReading? {
        guard let battery = sources.first(where: { $0[typeKey] as? String == internalBatteryType }),
              let current = battery[currentCapacityKey] as? Int,
              let capacity = battery[maxCapacityKey] as? Int,
              capacity > 0
        else { return nil }
        let onBattery = battery[stateKey] as? String == batteryPowerState
        let percent = max(0, min(100, current * 100 / capacity))
        return BatteryReading(onBattery: onBattery, percent: percent)
    }
}
