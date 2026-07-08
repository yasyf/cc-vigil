import CCVigilShared
import Foundation
import IOKit
import os

protocol ThermalReading: Sendable {
    func readCelsius() -> Double?
}

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var padding0: UInt8 = 0
    var padding1: UInt8 = 0
    var padding2: UInt8 = 0
}

/// Mirrors the AppleSMC user-client ABI: the explicit padding fields keep the
/// Swift layout byte-identical to the 80-byte C struct, asserted in init.
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var padding0: UInt16 = 0
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var padding1: UInt8 = 0
    var data32: UInt32 = 0
    // swiftlint:disable:next large_tuple - AppleSMC ABI: a fixed 32-byte payload
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

final class SMCThermalReader: ThermalReading, @unchecked Sendable {
    private static let handleYPCEventSelector: UInt32 = 2
    private static let readKeyCommand: UInt8 = 5
    private static let keyFromIndexCommand: UInt8 = 8
    private static let keyInfoCommand: UInt8 = 9

    private let connection: io_connect_t
    private let sensors = OSAllocatedUnfairLock<[(sensor: ThermalSensor, size: Int)]>(initialState: [])

    init?() {
        precondition(
            MemoryLayout<SMCParamStruct>.size == 80,
            "SMCParamStruct must be exactly 80 bytes, got \(MemoryLayout<SMCParamStruct>.size)"
        )
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            Logger.monitors.error("AppleSMC service not found; thermal cutout disabled")
            return nil
        }
        defer { IOObjectRelease(service) }
        var opened: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &opened) == kIOReturnSuccess else {
            Logger.monitors.error("IOServiceOpen(AppleSMC) failed; thermal cutout disabled")
            return nil
        }
        connection = opened
    }

    deinit {
        IOServiceClose(connection)
    }

    func readCelsius() -> Double? {
        let selected = currentSensors()
        guard !selected.isEmpty else { return nil }
        let readings = selected.compactMap { entry -> Double? in
            guard let bytes = readBytes(key: entry.sensor.key, size: entry.size) else { return nil }
            return ThermalSensors.celsius(type: entry.sensor.type, bytes: bytes)
        }
        return ThermalSensors.averageCelsius(readings)
    }

    /// An empty discovery is never cached: SMC hiccups at boot would otherwise
    /// permanently disable the thermal cutout.
    private func currentSensors() -> [(sensor: ThermalSensor, size: Int)] {
        sensors.withLock { cached in
            if !cached.isEmpty {
                return cached
            }
            let discovered = discoverSensors()
            if !discovered.isEmpty {
                cached = discovered
                Logger.monitors.info(
                    "discovered \(discovered.count, privacy: .public) SMC thermal sensors"
                )
            }
            return discovered
        }
    }

    private func discoverSensors() -> [(sensor: ThermalSensor, size: Int)] {
        guard let countInfo = keyInfo("#KEY"),
              let countBytes = readBytes(key: "#KEY", size: countInfo.size),
              let total = SMCValue.uint32(bytes: countBytes)
        else { return [] }
        var available: [ThermalSensor] = []
        var sizes: [String: Int] = [:]
        for index in 0 ..< total {
            guard let key = keyName(atIndex: index) else { continue }
            let candidate = ThermalSensors.appleSiliconPrefixes.contains(where: key.hasPrefix)
                || ThermalSensors.intelFallbackKeys.contains(key)
            guard candidate, let info = keyInfo(key) else { continue }
            available.append(ThermalSensor(key: key, type: info.type))
            sizes[key] = info.size
        }
        return ThermalSensors.select(available: available).compactMap { sensor in
            sizes[sensor.key].map { (sensor, $0) }
        }
    }

    private func keyInfo(_ key: String) -> (type: String, size: Int)? {
        var input = SMCParamStruct()
        input.key = SMCValue.fourCC(key)
        input.data8 = Self.keyInfoCommand
        guard let output = call(&input) else { return nil }
        return (SMCValue.name(fromFourCC: output.keyInfo.dataType), Int(output.keyInfo.dataSize))
    }

    private func readBytes(key: String, size: Int) -> [UInt8]? {
        var input = SMCParamStruct()
        input.key = SMCValue.fourCC(key)
        input.keyInfo.dataSize = UInt32(size)
        input.data8 = Self.readKeyCommand
        guard let output = call(&input) else { return nil }
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
    }

    private func keyName(atIndex index: UInt32) -> String? {
        var input = SMCParamStruct()
        input.data8 = Self.keyFromIndexCommand
        input.data32 = index
        guard let output = call(&input) else { return nil }
        return SMCValue.name(fromFourCC: output.key)
    }

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.size
        let status = IOConnectCallStructMethod(
            connection,
            Self.handleYPCEventSelector,
            &input,
            MemoryLayout<SMCParamStruct>.size,
            &output,
            &outputSize
        )
        guard status == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }
}
