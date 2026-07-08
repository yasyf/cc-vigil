public enum SMCValue {
    public static func fourCC(_ name: String) -> UInt32 {
        let scalars = Array(name.unicodeScalars)
        precondition(
            scalars.count == 4 && scalars.allSatisfy { $0.value < 0x80 },
            "SMC key must be 4 ASCII characters: \(name)"
        )
        return scalars.reduce(into: UInt32(0)) { $0 = $0 << 8 | UInt32($1.value) }
    }

    public static func name(fromFourCC code: UInt32) -> String {
        let scalars = stride(from: 24, through: 0, by: -8).map { shift in
            Unicode.Scalar(UInt8((code >> UInt32(shift)) & 0xFF))
        }
        return String(String.UnicodeScalarView(scalars))
    }

    public static func float32(bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let value = Float(bitPattern: bits)
        guard value.isFinite else { return nil }
        return Double(value)
    }

    public static func sp78(bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return Double(raw) / 256.0
    }

    public static func uint32(bytes: [UInt8]) -> UInt32? {
        guard bytes.count >= 4 else { return nil }
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }
}

public struct ThermalSensor: Hashable, Sendable {
    public let key: String
    public let type: String

    public init(key: String, type: String) {
        self.key = key
        self.type = type
    }
}

public enum ThermalSensors {
    public static let appleSiliconPrefixes = ["Tp", "Te"]
    public static let appleSiliconType = "flt "
    public static let intelFallbackKeys = ["TC0P", "TC0D"]
    public static let intelType = "sp78"
    public static let plausibleCelsius = 1.0 ... 125.0

    public static func select(available: [ThermalSensor]) -> [ThermalSensor] {
        let silicon = available.filter { sensor in
            sensor.type == appleSiliconType
                && appleSiliconPrefixes.contains(where: sensor.key.hasPrefix)
        }
        guard silicon.isEmpty else { return silicon }
        for key in intelFallbackKeys {
            if let sensor = available.first(where: { $0.key == key && $0.type == intelType }) {
                return [sensor]
            }
        }
        return []
    }

    public static func celsius(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case appleSiliconType: SMCValue.float32(bytes: bytes)
        case intelType: SMCValue.sp78(bytes: bytes)
        default: nil
        }
    }

    public static func averageCelsius(_ readings: [Double]) -> Double? {
        let plausible = readings.filter { plausibleCelsius.contains($0) }
        guard !plausible.isEmpty else { return nil }
        return plausible.reduce(0, +) / Double(plausible.count)
    }
}
