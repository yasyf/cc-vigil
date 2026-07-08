import CCVigilShared
import Foundation

/// Test-only battery seam: when `CC_VIGIL_FAKE_BATTERY_FILE` names a file,
/// the daemon polls it instead of IOPS so headless runs can drive the battery
/// cutout. The file holds one line — `battery <percent>` or `ac <percent>`.
public enum FakeBatteryFile {
    public static let environmentKey = "CC_VIGIL_FAKE_BATTERY_FILE"

    public static func reading(fromContents contents: String) -> BatteryReading? {
        let tokens = contents.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 2, let percent = Int(tokens[1]) else { return nil }
        switch tokens[0] {
        case "battery":
            return BatteryReading(onBattery: true, percent: percent)
        case "ac":
            return BatteryReading(onBattery: false, percent: percent)
        default:
            return nil
        }
    }
}
