import Foundation

public enum VigilConfigError: Error, Equatable {
    case outOfRange(field: String, allowed: String)
}

public struct VigilConfig: Codable, Equatable, Sendable {
    public static let batteryFloorPercentRange = 5 ... 50
    public static let thermalCutoutCelsiusRange = 70.0 ... 95.0
    public static let pollBlockingSecondsRange = 1 ... 300
    public static let pollIdleSecondsRange = 1 ... 600
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
    public let lowPowerCutout: Bool
    public let transcriptsRoots: [String]

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
        lowPowerCutout = true
        transcriptsRoots = []
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
        notifyOnCutout: Bool = Self.default.notifyOnCutout,
        lowPowerCutout: Bool = Self.default.lowPowerCutout,
        transcriptsRoots: [String] = Self.default.transcriptsRoots
    ) throws {
        guard Self.batteryFloorPercentRange.contains(batteryFloorPercent) else {
            throw VigilConfigError.outOfRange(field: "batteryFloorPercent", allowed: "5-50")
        }
        guard Self.thermalCutoutCelsiusRange.contains(thermalCutoutCelsius) else {
            throw VigilConfigError.outOfRange(field: "thermalCutoutCelsius", allowed: "70-95")
        }
        guard Self.pollBlockingSecondsRange.contains(pollBlockingSeconds) else {
            throw VigilConfigError.outOfRange(field: "pollBlockingSeconds", allowed: "1-300")
        }
        guard Self.pollIdleSecondsRange.contains(pollIdleSeconds) else {
            throw VigilConfigError.outOfRange(field: "pollIdleSeconds", allowed: "1-600")
        }
        let positiveFields = [
            ("activityWindowSeconds", activityWindowSeconds),
            ("pendingAsyncMaxAgeSeconds", pendingAsyncMaxAgeSeconds),
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
        self.lowPowerCutout = lowPowerCutout
        self.transcriptsRoots = transcriptsRoots
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            from: decoder,
            required: [
                "activityWindowSeconds",
                "batteryFloorPercent",
                "hideMenuBarExtra",
                "lowPowerCutout",
                "notifyOnCutout",
                "notifyOnRelease",
                "pendingAsyncMaxAgeSeconds",
                "pollBlockingSeconds",
                "pollIdleSeconds",
                "thermalCutoutCelsius",
                "transcriptsRoots",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            batteryFloorPercent: container.decode(Int.self, forKey: .batteryFloorPercent),
            thermalCutoutCelsius: container.decode(Double.self, forKey: .thermalCutoutCelsius),
            activityWindowSeconds: container.decode(Int.self, forKey: .activityWindowSeconds),
            pendingAsyncMaxAgeSeconds: container.decode(Int.self, forKey: .pendingAsyncMaxAgeSeconds),
            pollBlockingSeconds: container.decode(Int.self, forKey: .pollBlockingSeconds),
            pollIdleSeconds: container.decode(Int.self, forKey: .pollIdleSeconds),
            hideMenuBarExtra: container.decode(Bool.self, forKey: .hideMenuBarExtra),
            notifyOnRelease: container.decode(Bool.self, forKey: .notifyOnRelease),
            notifyOnCutout: container.decode(Bool.self, forKey: .notifyOnCutout),
            lowPowerCutout: container.decode(Bool.self, forKey: .lowPowerCutout),
            transcriptsRoots: container.decode([String].self, forKey: .transcriptsRoots)
        )
    }
}
