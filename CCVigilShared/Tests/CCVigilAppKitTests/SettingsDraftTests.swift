import CCVigilAppKit
import CCVigilShared
import Testing

private enum EditableField: String, CaseIterable {
    case batteryFloorPercent
    case thermalCutoutCelsius
    case activityWindowSeconds
    case hideMenuBarExtra
    case notifyOnRelease
    case notifyOnCutout
    case lowPowerCutout
}

private func config(
    batteryFloorPercent: Int = 35,
    thermalCutoutCelsius: Double = 88,
    activityWindowSeconds: Int = 600,
    pendingAsyncMaxAgeSeconds: Int = 21600,
    pollBlockingSeconds: Int = 30,
    pollIdleSeconds: Int = 90,
    hideMenuBarExtra: Bool = true,
    notifyOnRelease: Bool = false,
    notifyOnCutout: Bool = false,
    lowPowerCutout: Bool = false,
    transcriptsRoots: [String] = ["/roots/a", "/roots/b"]
) throws -> VigilConfig {
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
        lowPowerCutout: lowPowerCutout,
        transcriptsRoots: transcriptsRoots
    )
}

@Test
private func rewriteWithNoChangePreservesEveryField() throws {
    let base = try config()
    #expect(try SettingsDraft(base).resolved() == base)
}

@Test(arguments: EditableField.allCases)
private func settingsRewritePreservesEveryUntouchedField(field: EditableField) throws {
    var draft = try SettingsDraft(config())
    let expected: VigilConfig
    switch field {
    case .batteryFloorPercent:
        draft.batteryFloorPercent = 12
        expected = try config(batteryFloorPercent: 12)
    case .thermalCutoutCelsius:
        draft.thermalCutoutCelsius = 91
        expected = try config(thermalCutoutCelsius: 91)
    case .activityWindowSeconds:
        draft.activityWindowSeconds = 120
        expected = try config(activityWindowSeconds: 120)
    case .hideMenuBarExtra:
        draft.hideMenuBarExtra = false
        expected = try config(hideMenuBarExtra: false)
    case .notifyOnRelease:
        draft.notifyOnRelease = true
        expected = try config(notifyOnRelease: true)
    case .notifyOnCutout:
        draft.notifyOnCutout = true
        expected = try config(notifyOnCutout: true)
    case .lowPowerCutout:
        draft.lowPowerCutout = true
        expected = try config(lowPowerCutout: true)
    }
    #expect(try draft.resolved() == expected)
}
