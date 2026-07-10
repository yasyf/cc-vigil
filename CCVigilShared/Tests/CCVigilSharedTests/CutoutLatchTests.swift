import CCVigilShared
import Testing

private func sample(
    onBattery: Bool = false,
    batteryPercent: Int = 100,
    thermalCelsius: Double? = nil,
    lidClosed: Bool = false,
    blocking: Bool = false,
    lowPowerEnabled: Bool = false
) -> PowerSample {
    PowerSample(
        onBattery: onBattery,
        batteryPercent: batteryPercent,
        thermalCelsius: thermalCelsius,
        lidClosed: lidClosed,
        blocking: blocking,
        lowPowerEnabled: lowPowerEnabled
    )
}

private func defaultLatch() -> CutoutLatch {
    CutoutLatch(config: .default)
}

@Test(arguments: [
    (true, 19, true),
    (true, 20, false),
    (false, 1, false),
])
func batteryCutoutFiresBelowFloorOnBatteryOnly(onBattery: Bool, percent: Int, expectLatched: Bool) {
    var latch = defaultLatch()
    let events = latch.update(with: sample(onBattery: onBattery, batteryPercent: percent))
    #expect(events == (expectLatched ? [.latched(.battery)] : []))
    #expect(latch.latched.contains(.battery) == expectLatched)
}

@Test func batteryCutoutIgnoresLidAndBlocking() {
    var latch = defaultLatch()
    let events = latch.update(with: sample(onBattery: true, batteryPercent: 10, lidClosed: false, blocking: false))
    #expect(events == [.latched(.battery)])
}

@Test(arguments: [
    (true, 24, false),
    (true, 25, true),
    (false, 10, true),
])
func batteryLatchClearsWithHysteresisOrAC(onBattery: Bool, percent: Int, expectCleared: Bool) {
    var latch = defaultLatch()
    #expect(latch.update(with: sample(onBattery: true, batteryPercent: 10)) == [.latched(.battery)])
    let events = latch.update(with: sample(onBattery: onBattery, batteryPercent: percent))
    #expect(events == (expectCleared ? [.cleared(.battery)] : []))
    #expect(latch.latched.contains(.battery) == !expectCleared)
}

@Test func batteryLatchRejectsReacquireWhileLatched() {
    var latch = defaultLatch()
    _ = latch.update(with: sample(onBattery: true, batteryPercent: 10))
    #expect(latch.rejectsAcquire == true)
    #expect(latch.rejectionReasons == ["cutout-battery"])
    #expect(latch.update(with: sample(onBattery: true, batteryPercent: 10)) == [])
    #expect(latch.rejectsAcquire == true)
}

@Test(arguments: [
    (true, true, 80.0, true),
    (true, true, 79.9, false),
    (false, true, 95.0, false),
    (true, false, 95.0, false),
])
func thermalCutoutFiresOnlyLidClosedAndBlocking(
    lidClosed: Bool,
    blocking: Bool,
    celsius: Double,
    expectLatched: Bool
) {
    var latch = defaultLatch()
    let events = latch.update(with: sample(thermalCelsius: celsius, lidClosed: lidClosed, blocking: blocking))
    #expect(events == (expectLatched ? [.latched(.thermal)] : []))
    #expect(latch.latched.contains(.thermal) == expectLatched)
}

@Test func thermalCutoutNeedsAReading() {
    var latch = defaultLatch()
    #expect(latch.update(with: sample(thermalCelsius: nil, lidClosed: true, blocking: true)) == [])
    #expect(latch.latched.isEmpty)
}

@Test(arguments: [
    (76.0, true, false),
    (75.0, true, true),
    (90.0, false, true),
])
func thermalLatchClearsWithHysteresisOrLidOpen(celsius: Double, lidClosed: Bool, expectCleared: Bool) {
    var latch = defaultLatch()
    #expect(latch.update(with: sample(thermalCelsius: 85, lidClosed: true, blocking: true)) == [.latched(.thermal)])
    let events = latch.update(with: sample(thermalCelsius: celsius, lidClosed: lidClosed, blocking: true))
    #expect(events == (expectCleared ? [.cleared(.thermal)] : []))
    #expect(latch.latched.contains(.thermal) == !expectCleared)
}

@Test func thermalLatchHoldsWithoutAReadingWhileLidClosed() {
    var latch = defaultLatch()
    _ = latch.update(with: sample(thermalCelsius: 85, lidClosed: true, blocking: true))
    #expect(latch.update(with: sample(thermalCelsius: nil, lidClosed: true, blocking: true)) == [])
    #expect(latch.latched == [.thermal])
}

@Test(arguments: [true, false])
func lowPowerCutoutFiresWhileEnabled(enabled: Bool) {
    var latch = defaultLatch()
    let events = latch.update(with: sample(lowPowerEnabled: enabled))
    #expect(events == (enabled ? [.latched(.lowPower)] : []))
    #expect(latch.latched.contains(.lowPower) == enabled)
}

@Test func lowPowerCutoutIgnoresBatteryThermalAndLid() {
    var latch = defaultLatch()
    let events = latch.update(with: sample(
        onBattery: false,
        batteryPercent: 100,
        thermalCelsius: 20,
        lidClosed: false,
        blocking: false,
        lowPowerEnabled: true
    ))
    #expect(events == [.latched(.lowPower)])
    #expect(latch.rejectionReasons == ["cutout-low-power"])
}

@Test func lowPowerLatchClearsImmediatelyWhenDisabled() {
    var latch = defaultLatch()
    #expect(latch.update(with: sample(lowPowerEnabled: true)) == [.latched(.lowPower)])
    #expect(latch.update(with: sample(lowPowerEnabled: true)) == [])
    #expect(latch.update(with: sample(lowPowerEnabled: false)) == [.cleared(.lowPower)])
    #expect(latch.latched.isEmpty)
}

@Test func allThreeCutoutsLatchInOneUpdate() {
    var latch = defaultLatch()
    let events = latch.update(with: sample(
        onBattery: true,
        batteryPercent: 5,
        thermalCelsius: 90,
        lidClosed: true,
        blocking: true,
        lowPowerEnabled: true
    ))
    #expect(events == [.latched(.battery), .latched(.thermal), .latched(.lowPower)])
    #expect(latch.latched == [.battery, .thermal, .lowPower])
    #expect(latch.rejectionReasons == ["cutout-battery", "cutout-low-power", "cutout-thermal"])
}

@Test func bothCutoutsLatchInOneUpdate() {
    var latch = defaultLatch()
    let events = latch.update(with: sample(
        onBattery: true,
        batteryPercent: 5,
        thermalCelsius: 90,
        lidClosed: true,
        blocking: true
    ))
    #expect(events == [.latched(.battery), .latched(.thermal)])
    #expect(latch.latched == [.battery, .thermal])
    #expect(latch.rejectionReasons == ["cutout-battery", "cutout-thermal"])
}

@Test func cutoutThresholdsComeFromConfig() throws {
    var latch = try CutoutLatch(config: VigilConfig(batteryFloorPercent: 30, thermalCutoutCelsius: 70))
    let events = latch.update(with: sample(
        onBattery: true,
        batteryPercent: 29,
        thermalCelsius: 70,
        lidClosed: true,
        blocking: true
    ))
    #expect(events == [.latched(.battery), .latched(.thermal)])
    let nearRecovery = sample(
        onBattery: true, batteryPercent: 34, thermalCelsius: 65.1, lidClosed: true, blocking: true
    )
    #expect(latch.update(with: nearRecovery) == [])
    let recovered = sample(onBattery: true, batteryPercent: 35, thermalCelsius: 65, lidClosed: true, blocking: true)
    #expect(latch.update(with: recovered) == [.cleared(.battery), .cleared(.thermal)])
}

@Test func unlatchedIsCalm() {
    let latch = defaultLatch()
    #expect(latch.rejectsAcquire == false)
    #expect(latch.rejectionReasons == [])
}
