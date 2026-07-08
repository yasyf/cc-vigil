import CCVigilShared
import Testing

@Test func fourCCRoundTrips() {
    let code = SMCValue.fourCC("#KEY")
    #expect(code == 0x234B_4559)
    #expect(SMCValue.name(fromFourCC: code) == "#KEY")
    #expect(SMCValue.name(fromFourCC: SMCValue.fourCC("Tp01")) == "Tp01")
}

@Test func float32DecodesLittleEndian() {
    #expect(SMCValue.float32(bytes: [0x00, 0x00, 0x80, 0x42]) == 64.0)
    #expect(SMCValue.float32(bytes: [0x66, 0xE6, 0x7A, 0x42]) == Double(Float(62.725)))
}

@Test func float32RejectsShortOrNonFinite() {
    #expect(SMCValue.float32(bytes: [0x00, 0x00]) == nil)
    #expect(SMCValue.float32(bytes: [0x00, 0x00, 0x80, 0x7F]) == nil)
}

@Test func sp78DecodesBigEndianFixedPoint() {
    #expect(SMCValue.sp78(bytes: [0x40, 0x80]) == 64.5)
    #expect(SMCValue.sp78(bytes: [0xFF, 0x00]) == -1.0)
    #expect(SMCValue.sp78(bytes: [0x00]) == nil)
}

@Test func uint32DecodesBigEndian() {
    #expect(SMCValue.uint32(bytes: [0x00, 0x00, 0x08, 0x53]) == 2131)
    #expect(SMCValue.uint32(bytes: [0x08]) == nil)
}

@Test func selectPrefersAppleSiliconFloatSensors() {
    let selected = ThermalSensors.select(available: [
        ThermalSensor(key: "TC0P", type: "sp78"),
        ThermalSensor(key: "Tp01", type: "flt "),
        ThermalSensor(key: "Te05", type: "flt "),
        ThermalSensor(key: "Tp0X", type: "ui16"),
        ThermalSensor(key: "TW0P", type: "flt "),
    ])
    #expect(selected == [
        ThermalSensor(key: "Tp01", type: "flt "),
        ThermalSensor(key: "Te05", type: "flt "),
    ])
}

@Test func selectFallsBackToIntelKeysInOrder() {
    let both = ThermalSensors.select(available: [
        ThermalSensor(key: "TC0D", type: "sp78"),
        ThermalSensor(key: "TC0P", type: "sp78"),
    ])
    #expect(both == [ThermalSensor(key: "TC0P", type: "sp78")])
    let dieOnly = ThermalSensors.select(available: [ThermalSensor(key: "TC0D", type: "sp78")])
    #expect(dieOnly == [ThermalSensor(key: "TC0D", type: "sp78")])
    #expect(ThermalSensors.select(available: []) == [])
}

@Test func celsiusDecodesPerSensorType() {
    #expect(ThermalSensors.celsius(type: "flt ", bytes: [0x00, 0x00, 0x80, 0x42]) == 64.0)
    #expect(ThermalSensors.celsius(type: "sp78", bytes: [0x40, 0x80]) == 64.5)
    #expect(ThermalSensors.celsius(type: "ui16", bytes: [0x40, 0x80]) == nil)
}

@Test func averageFiltersImplausibleReadings() {
    #expect(ThermalSensors.averageCelsius([60, 70, 0, 200, -3]) == 65)
    #expect(ThermalSensors.averageCelsius([0, 126]) == nil)
    #expect(ThermalSensors.averageCelsius([]) == nil)
}
