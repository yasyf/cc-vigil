import CCVigilShared

public struct SettingsDraft: Equatable, Sendable {
    public var batteryFloorPercent: Int
    public var thermalCutoutCelsius: Double
    public var activityWindowSeconds: Int
    public var hideMenuBarExtra: Bool
    public var notifyOnRelease: Bool
    public var notifyOnCutout: Bool

    public let pendingAsyncMaxAgeSeconds: Int
    public let pollBlockingSeconds: Int
    public let pollIdleSeconds: Int
    public let transcriptsRoots: [String]

    public init(_ config: VigilConfig) {
        batteryFloorPercent = config.batteryFloorPercent
        thermalCutoutCelsius = config.thermalCutoutCelsius
        activityWindowSeconds = config.activityWindowSeconds
        hideMenuBarExtra = config.hideMenuBarExtra
        notifyOnRelease = config.notifyOnRelease
        notifyOnCutout = config.notifyOnCutout
        pendingAsyncMaxAgeSeconds = config.pendingAsyncMaxAgeSeconds
        pollBlockingSeconds = config.pollBlockingSeconds
        pollIdleSeconds = config.pollIdleSeconds
        transcriptsRoots = config.transcriptsRoots
    }

    public func resolved() throws -> VigilConfig {
        try VigilConfig(
            batteryFloorPercent: batteryFloorPercent,
            thermalCutoutCelsius: thermalCutoutCelsius,
            activityWindowSeconds: activityWindowSeconds,
            pendingAsyncMaxAgeSeconds: pendingAsyncMaxAgeSeconds,
            pollBlockingSeconds: pollBlockingSeconds,
            pollIdleSeconds: pollIdleSeconds,
            hideMenuBarExtra: hideMenuBarExtra,
            notifyOnRelease: notifyOnRelease,
            notifyOnCutout: notifyOnCutout,
            transcriptsRoots: transcriptsRoots
        )
    }
}
