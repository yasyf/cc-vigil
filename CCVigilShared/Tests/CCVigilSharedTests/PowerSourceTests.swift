import CCVigilShared
import Foundation
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

@Test(arguments: [
    (BatteryReading?.none, BatteryReading(onBattery: true, percent: 80), false),
    (BatteryReading(onBattery: false, percent: 80), BatteryReading(onBattery: true, percent: 80), true),
    (BatteryReading(onBattery: true, percent: 80), BatteryReading(onBattery: false, percent: 80), true),
    (BatteryReading(onBattery: true, percent: 42), BatteryReading(onBattery: true, percent: 50), false),
    (BatteryReading(onBattery: false, percent: 90), BatteryReading(onBattery: false, percent: 100), false),
])
func detectsPowerSourceTransition(previous: BatteryReading?, current: BatteryReading, expected: Bool) {
    #expect(PowerSourceTransition.occurred(from: previous, to: current) == expected)
}

@Test(arguments: [
    (BatteryReading?.none, BatteryReading(onBattery: false, percent: 100), true, true, false),
    (BatteryReading(onBattery: false, percent: 90), BatteryReading(onBattery: false, percent: 90), true, false, false),
    (BatteryReading(onBattery: false, percent: 90), BatteryReading(onBattery: true, percent: 90), true, true, true),
    (BatteryReading(onBattery: true, percent: 90), BatteryReading(onBattery: false, percent: 90), true, true, true),
    (BatteryReading(onBattery: false, percent: 90), BatteryReading(onBattery: true, percent: 90), false, true, false),
    (BatteryReading(onBattery: false, percent: 90), BatteryReading(onBattery: false, percent: 40), true, true, false),
])
func batteryWriteDecidesStorageAndReassert(
    current: BatteryReading?,
    reading: BatteryReading,
    desiredBlocking: Bool,
    stored: Bool,
    reassert: Bool
) {
    let write = BatteryWrite(current: current, reading: reading, desiredBlocking: desiredBlocking)
    #expect(write.stored == stored)
    #expect(write.reassert == reassert)
}

private let powerEpoch = Date(timeIntervalSince1970: 1_000_000)

/// Mirrors DaemonCore's single battery funnel: every write — the closed-lid
/// safety poll and the IOPS callback alike — routes through BatteryWrite, so a
/// power-source flip forces a PushDecider re-assert regardless of which path
/// observed it first.
private struct BatteryFunnel {
    var battery: BatteryReading?
    var decider = PushDecider(reconcileSeconds: 60)
    var desiredBlocking = true

    mutating func write(_ reading: BatteryReading) {
        let write = BatteryWrite(current: battery, reading: reading, desiredBlocking: desiredBlocking)
        guard write.stored else { return }
        battery = reading
        if write.reassert {
            decider.forceReassert()
        }
    }

    mutating func settle(now: Date) {
        guard let plan = decider.plan(desired: true, now: now) else { return }
        decider.record(desired: true, settled: true, generation: plan.generation, at: now)
    }

    func reassertPending(now: Date) -> Bool {
        decider.plan(desired: true, now: now) != nil
    }
}

@Test func safetyPollFlipWhileBlockingReasserts() {
    let now = powerEpoch
    var funnel = BatteryFunnel()
    funnel.write(BatteryReading(onBattery: false, percent: 90))
    funnel.settle(now: now)
    #expect(funnel.reassertPending(now: now) == false)

    funnel.write(BatteryReading(onBattery: true, percent: 90))
    #expect(funnel.reassertPending(now: now))
}

@Test func sameSourceSafetyPollTickDoesNotReassert() {
    let now = powerEpoch
    var funnel = BatteryFunnel()
    funnel.write(BatteryReading(onBattery: true, percent: 90))
    funnel.settle(now: now)
    #expect(funnel.reassertPending(now: now) == false)

    funnel.write(BatteryReading(onBattery: true, percent: 80))
    #expect(funnel.reassertPending(now: now) == false)
}

@Test func safetyPollTransitionSurvivesARedundantIopsCallback() {
    let now = powerEpoch
    var funnel = BatteryFunnel()
    funnel.write(BatteryReading(onBattery: false, percent: 90))
    funnel.settle(now: now)

    funnel.write(BatteryReading(onBattery: true, percent: 90))
    funnel.write(BatteryReading(onBattery: true, percent: 90))
    #expect(funnel.reassertPending(now: now))
}
