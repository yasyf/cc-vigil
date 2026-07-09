import CCVigilShared
import Foundation
import Testing

@Test func configDefaults() {
    let config = VigilConfig.default
    #expect(config.batteryFloorPercent == 20)
    #expect(config.thermalCutoutCelsius == 80)
    #expect(config.activityWindowSeconds == 300)
    #expect(config.pendingAsyncMaxAgeSeconds == 43200)
    #expect(config.pollBlockingSeconds == 15)
    #expect(config.pollIdleSeconds == 45)
    #expect(config.hideMenuBarExtra == false)
    #expect(config.notifyOnRelease == true)
    #expect(config.notifyOnCutout == true)
}

@Test(arguments: [(5, 70.0), (50, 95.0)])
func configAcceptsRangeBoundaries(batteryFloor: Int, thermalCutout: Double) throws {
    let config = try VigilConfig(batteryFloorPercent: batteryFloor, thermalCutoutCelsius: thermalCutout)
    #expect(config.batteryFloorPercent == batteryFloor)
    #expect(config.thermalCutoutCelsius == thermalCutout)
}

@Test(arguments: [
    ("batteryFloorPercent", "4", "5-50"),
    ("batteryFloorPercent", "51", "5-50"),
    ("thermalCutoutCelsius", "69.9", "70-95"),
    ("thermalCutoutCelsius", "95.1", "70-95"),
    ("activityWindowSeconds", "0", ">= 1"),
    ("pendingAsyncMaxAgeSeconds", "0", ">= 1"),
    ("pollBlockingSeconds", "0", ">= 1"),
    ("pollIdleSeconds", "-1", ">= 1"),
])
func configRejectsOutOfRange(field: String, value: String, allowed: String) {
    let json = Data(#"{"\#(field)": \#(value)}"#.utf8)
    #expect(throws: VigilConfigError.outOfRange(field: field, allowed: allowed)) {
        try JSONDecoder().decode(VigilConfig.self, from: json)
    }
}

@Test func configDecodesEmptyObjectToDefaults() throws {
    let config = try JSONDecoder().decode(VigilConfig.self, from: Data("{}".utf8))
    #expect(config == .default)
}

@Test func configDecodesPartialObjectKeepingOtherDefaults() throws {
    let json = Data(#"{"batteryFloorPercent": 30, "pollIdleSeconds": 90}"#.utf8)
    let config = try JSONDecoder().decode(VigilConfig.self, from: json)
    #expect(config.batteryFloorPercent == 30)
    #expect(config.pollIdleSeconds == 90)
    #expect(config.thermalCutoutCelsius == 80)
    #expect(config.activityWindowSeconds == 300)
    #expect(config.pendingAsyncMaxAgeSeconds == 43200)
    #expect(config.pollBlockingSeconds == 15)
    #expect(config.hideMenuBarExtra == false)
    #expect(config.notifyOnRelease == true)
    #expect(config.notifyOnCutout == true)
}

@Test func configRoundTripsThroughJSON() throws {
    let original = try VigilConfig(
        batteryFloorPercent: 35,
        thermalCutoutCelsius: 72.5,
        activityWindowSeconds: 120,
        pendingAsyncMaxAgeSeconds: 3600,
        pollBlockingSeconds: 10,
        pollIdleSeconds: 60,
        hideMenuBarExtra: true,
        notifyOnRelease: false,
        notifyOnCutout: false
    )
    let decoded = try JSONDecoder().decode(VigilConfig.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}
