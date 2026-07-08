import CCVigilShared
import Testing

private func batterySource(
    state: String = "Battery Power",
    current: Int = 42,
    max maxCapacity: Int = 100
) -> [String: Any] {
    [
        "Type": "InternalBattery",
        "Power Source State": state,
        "Current Capacity": current,
        "Max Capacity": maxCapacity,
    ]
}

@Test func parsesInternalBatteryOnBattery() {
    let reading = BatterySourceParser.reading(fromSources: [batterySource()])
    #expect(reading == BatteryReading(onBattery: true, percent: 42))
}

@Test func parsesACPowerAsNotOnBattery() {
    let reading = BatterySourceParser.reading(fromSources: [batterySource(state: "AC Power")])
    #expect(reading == BatteryReading(onBattery: false, percent: 42))
}

@Test func scalesCapacityToPercent() {
    let reading = BatterySourceParser.reading(fromSources: [batterySource(current: 3000, max: 6000)])
    #expect(reading?.percent == 50)
}

@Test func clampsPercentTo100() {
    let reading = BatterySourceParser.reading(fromSources: [batterySource(current: 105, max: 100)])
    #expect(reading?.percent == 100)
}

@Test func noInternalBatteryYieldsNil() {
    let ups: [String: Any] = ["Type": "UPS", "Current Capacity": 90, "Max Capacity": 100]
    #expect(BatterySourceParser.reading(fromSources: [ups]) == nil)
    #expect(BatterySourceParser.reading(fromSources: []) == nil)
}

@Test func zeroMaxCapacityYieldsNil() {
    #expect(BatterySourceParser.reading(fromSources: [batterySource(max: 0)]) == nil)
}

@Test func skipsNonBatterySourcesToFindTheBattery() {
    let ups: [String: Any] = ["Type": "UPS"]
    let reading = BatterySourceParser.reading(fromSources: [ups, batterySource(current: 7)])
    #expect(reading == BatteryReading(onBattery: true, percent: 7))
}
