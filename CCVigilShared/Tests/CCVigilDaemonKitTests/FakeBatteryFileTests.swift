import CCVigilDaemonKit
import CCVigilShared
import Testing

@Test(arguments: [
    ("battery 15", BatteryReading(onBattery: true, percent: 15)),
    ("ac 100", BatteryReading(onBattery: false, percent: 100)),
    ("battery 0", BatteryReading(onBattery: true, percent: 0)),
    ("  ac   42\n", BatteryReading(onBattery: false, percent: 42)),
])
func parsesFakeBatteryContents(contents: String, expected: BatteryReading) {
    #expect(FakeBatteryFile.reading(fromContents: contents) == expected)
}

@Test(arguments: ["", "battery", "battery fifteen", "usb 50", "battery 15 extra"])
func rejectsMalformedFakeBatteryContents(contents: String) {
    #expect(FakeBatteryFile.reading(fromContents: contents) == nil)
}
