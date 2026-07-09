import Foundation

public enum VigilConfigError: Error, Equatable {
    case outOfRange(field: String, allowed: String)
}

public struct VigilConfig: Codable, Equatable, Sendable {
    public static let batteryFloorPercentRange = 5 ... 50
    public static let thermalCutoutCelsiusRange = 70.0 ... 95.0
    public static let `default` = VigilConfig()

    public let batteryFloorPercent: Int
    public let thermalCutoutCelsius: Double
    public let activityWindowSeconds: Int
    public let pendingAsyncMaxAgeSeconds: Int
    public let pollBlockingSeconds: Int
    public let pollIdleSeconds: Int
    public let hideMenuBarExtra: Bool
    public let notifyOnRelease: Bool
    public let notifyOnCutout: Bool

    private init() {
        batteryFloorPercent = 20
        thermalCutoutCelsius = 80
        activityWindowSeconds = 300
        pendingAsyncMaxAgeSeconds = 43200
        pollBlockingSeconds = 15
        pollIdleSeconds = 45
        hideMenuBarExtra = false
        notifyOnRelease = true
        notifyOnCutout = true
    }

    public init(
        batteryFloorPercent: Int = Self.default.batteryFloorPercent,
        thermalCutoutCelsius: Double = Self.default.thermalCutoutCelsius,
        activityWindowSeconds: Int = Self.default.activityWindowSeconds,
        pendingAsyncMaxAgeSeconds: Int = Self.default.pendingAsyncMaxAgeSeconds,
        pollBlockingSeconds: Int = Self.default.pollBlockingSeconds,
        pollIdleSeconds: Int = Self.default.pollIdleSeconds,
        hideMenuBarExtra: Bool = Self.default.hideMenuBarExtra,
        notifyOnRelease: Bool = Self.default.notifyOnRelease,
        notifyOnCutout: Bool = Self.default.notifyOnCutout
    ) throws {
        guard Self.batteryFloorPercentRange.contains(batteryFloorPercent) else {
            throw VigilConfigError.outOfRange(field: "batteryFloorPercent", allowed: "5-50")
        }
        guard Self.thermalCutoutCelsiusRange.contains(thermalCutoutCelsius) else {
            throw VigilConfigError.outOfRange(field: "thermalCutoutCelsius", allowed: "70-95")
        }
        let positiveFields = [
            ("activityWindowSeconds", activityWindowSeconds),
            ("pendingAsyncMaxAgeSeconds", pendingAsyncMaxAgeSeconds),
            ("pollBlockingSeconds", pollBlockingSeconds),
            ("pollIdleSeconds", pollIdleSeconds),
        ]
        for (field, value) in positiveFields where value < 1 {
            throw VigilConfigError.outOfRange(field: field, allowed: ">= 1")
        }
        self.batteryFloorPercent = batteryFloorPercent
        self.thermalCutoutCelsius = thermalCutoutCelsius
        self.activityWindowSeconds = activityWindowSeconds
        self.pendingAsyncMaxAgeSeconds = pendingAsyncMaxAgeSeconds
        self.pollBlockingSeconds = pollBlockingSeconds
        self.pollIdleSeconds = pollIdleSeconds
        self.hideMenuBarExtra = hideMenuBarExtra
        self.notifyOnRelease = notifyOnRelease
        self.notifyOnCutout = notifyOnCutout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            batteryFloorPercent: container
                .decodeIfPresent(Int.self, forKey: .batteryFloorPercent) ?? Self.default.batteryFloorPercent,
            thermalCutoutCelsius: container
                .decodeIfPresent(Double.self, forKey: .thermalCutoutCelsius) ?? Self.default.thermalCutoutCelsius,
            activityWindowSeconds: container
                .decodeIfPresent(Int.self, forKey: .activityWindowSeconds) ?? Self.default.activityWindowSeconds,
            pendingAsyncMaxAgeSeconds: container
                .decodeIfPresent(Int.self, forKey: .pendingAsyncMaxAgeSeconds) ?? Self.default
                .pendingAsyncMaxAgeSeconds,
            pollBlockingSeconds: container
                .decodeIfPresent(Int.self, forKey: .pollBlockingSeconds) ?? Self.default.pollBlockingSeconds,
            pollIdleSeconds: container
                .decodeIfPresent(Int.self, forKey: .pollIdleSeconds) ?? Self.default.pollIdleSeconds,
            hideMenuBarExtra: container
                .decodeIfPresent(Bool.self, forKey: .hideMenuBarExtra) ?? Self.default.hideMenuBarExtra,
            notifyOnRelease: container
                .decodeIfPresent(Bool.self, forKey: .notifyOnRelease) ?? Self.default.notifyOnRelease,
            notifyOnCutout: container
                .decodeIfPresent(Bool.self, forKey: .notifyOnCutout) ?? Self.default.notifyOnCutout
        )
    }
}
