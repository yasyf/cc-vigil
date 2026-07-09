import AppKit
import CCVigilAppKit
import CCVigilCLIKit
import CCVigilDaemonKit
import CCVigilShared
import Foundation
import Observation
import os

@MainActor
@Observable
final class AppModel {
    static let pauseToggleSeconds = 3600
    private static let firstRunCompletedKey = "firstRunCompleted"
    private static let lastMenuOpenedAtKey = "lastMenuOpenedAt"
    private static let daemonRestartDebounceSeconds = 1.5
    private static let launchOpenGraceSeconds = 5.0

    private(set) var status = StatusViewModel()
    private(set) var config: VigilConfig
    private(set) var awaySummary: AwaySummary?
    private(set) var commandError: String?
    private(set) var maintenanceMessage: String?
    private(set) var launchAtLogin = false
    private(set) var firstRunCompleted: Bool

    @ObservationIgnored private let paths: SupportPaths
    @ObservationIgnored private let commands: DaemonCommands
    @ObservationIgnored private let notifications = SleepNotificationController()
    @ObservationIgnored private let registrar = ServiceRegistrar()
    @ObservationIgnored private let launchedAt = Date()
    @ObservationIgnored private var daemonClient: DaemonClient?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var menuTrackingObserver: (any NSObjectProtocol)?

    init(supportDirectory: URL = SupportPaths.defaultDirectory) {
        let paths = SupportPaths(directory: supportDirectory)
        self.paths = paths
        commands = DaemonCommands(socketPath: paths.socketPath)
        firstRunCompleted = UserDefaults.standard.bool(forKey: Self.firstRunCompletedKey)
        do {
            try paths.ensureDirectory()
            config = try ConfigLoader.load(url: paths.configURL)
        } catch {
            fatalError("cc-vigil support directory unusable: \(error)")
        }
    }

    func start() {
        guard daemonClient == nil else { return }
        let client = DaemonClient { [weak self] event in
            guard let self else { return }
            status.apply(event)
            notifications.handle(event, settings: notificationSettings)
        }
        daemonClient = client
        client.start()
        // The menu-style MenuBarExtra keeps its content view alive, so
        // onAppear fires once at launch only; NSMenu tracking is the real
        // per-open signal (verified live — LSUIElement leaves no other menus).
        menuTrackingObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuOpened()
            }
        }
    }

    // MARK: - Menu

    var headline: String {
        status.headline(now: Date())
    }

    var pauseMenuTitle: String {
        status.pauseAction == .pause ? "Pause for 1 Hour" : "Resume"
    }

    func togglePause() {
        switch status.pauseAction {
        case .pause: send(.pause(seconds: Self.pauseToggleSeconds))
        case .resume: send(.pause(seconds: 0))
        }
    }

    func hold(seconds: Int) {
        let key = "app-\(UUID().uuidString.prefix(8).lowercased())"
        send(.hold(key: key, reason: "menu hold", ttlSeconds: seconds, pid: nil))
    }

    func releaseHold(key: String) {
        send(.release(key: key))
    }

    func menuOpened() {
        let now = Date()
        let defaults = UserDefaults.standard
        let storedEpoch = defaults.double(forKey: Self.lastMenuOpenedAtKey)
        let since = storedEpoch > 0 ? Date(timeIntervalSince1970: storedEpoch) : launchedAt
        // MenuBarExtra evaluates its content once while the scene is built, so
        // onAppear fires at launch too; that artifact must not consume the
        // away window before the user actually opens the menu.
        if now.timeIntervalSince(launchedAt) > Self.launchOpenGraceSeconds {
            defaults.set(now.timeIntervalSince1970, forKey: Self.lastMenuOpenedAtKey)
        }
        let eventsURL = paths.eventsURL
        Task {
            awaySummary = await Self.computeAwaySummary(eventsURL: eventsURL, since: since, now: now)
        }
    }

    private nonisolated static func computeAwaySummary(
        eventsURL: URL,
        since: Date,
        now: Date
    ) async -> AwaySummary? {
        guard let data = try? Data(contentsOf: eventsURL) else { return nil }
        let decoded = AwayDigest.decodeRecords(fromJSONL: data)
        if decoded.skippedLines > 0 {
            Logger.app.error("events.log: skipped \(decoded.skippedLines, privacy: .public) undecodable lines")
        }
        return AwayDigest.summarize(records: decoded.records, since: since, now: now)
    }

    private func send(_ request: WireRequest) {
        Task {
            do {
                switch try await commands.roundTrip(request) {
                case .ok, .status:
                    commandError = nil
                case let .error(message):
                    commandError = message
                }
            } catch {
                commandError = String(describing: error)
            }
        }
    }

    // MARK: - Config

    func setBatteryFloor(_ percent: Int) {
        updateConfig { $0.batteryFloorPercent = percent }
    }

    func setThermalCutout(_ celsius: Double) {
        updateConfig { $0.thermalCutoutCelsius = celsius }
    }

    func setActivityWindow(minutes: Int) {
        updateConfig { $0.activityWindowSeconds = minutes * 60 }
    }

    func setHideMenuBarExtra(_ hidden: Bool) {
        updateConfig { $0.hideMenuBarExtra = hidden }
    }

    func setNotifyOnRelease(_ enabled: Bool) {
        updateConfig { $0.notifyOnRelease = enabled }
    }

    func setNotifyOnCutout(_ enabled: Bool) {
        updateConfig { $0.notifyOnCutout = enabled }
    }

    private var notificationSettings: NotificationSettings {
        NotificationSettings(notifyOnRelease: config.notifyOnRelease, notifyOnCutout: config.notifyOnCutout)
    }

    private func updateConfig(_ mutate: (inout SettingsDraft) -> Void) {
        var draft = SettingsDraft(config)
        mutate(&draft)
        let updated: VigilConfig
        do {
            updated = try draft.resolved()
        } catch {
            // Every settings control clamps to VigilConfig's ranges.
            fatalError("settings produced an invalid config: \(error)")
        }
        guard updated != config else { return }
        let daemonCares = updated.batteryFloorPercent != config.batteryFloorPercent
            || updated.thermalCutoutCelsius != config.thermalCutoutCelsius
            || updated.activityWindowSeconds != config.activityWindowSeconds
        config = updated
        do {
            try ConfigLoader.save(updated, to: paths.configURL)
        } catch {
            maintenanceMessage = "config save failed: \(error)"
            return
        }
        if daemonCares {
            scheduleDaemonRestart()
        }
    }

    /// The daemon reads config.json only at startup; kickstart restarts it
    /// under launchd so new cutout/window values take effect.
    private func scheduleDaemonRestart() {
        restartTask?.cancel()
        restartTask = Task {
            try? await Task.sleep(for: .seconds(Self.daemonRestartDebounceSeconds))
            guard !Task.isCancelled else { return }
            let result = await Subprocess.run(
                executable: URL(fileURLWithPath: "/bin/launchctl"),
                arguments: ["kickstart", "-k", "gui/\(getuid())/dev.yasyf.cc-vigil.daemon"]
            )
            if result.status != 0 {
                Logger.app.error("daemon kickstart failed: \(result.output, privacy: .public)")
            }
        }
    }

    // MARK: - Settings actions

    func refreshLaunchAtLogin() {
        launchAtLogin = registrar.launchAtLoginEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try registrar.setLaunchAtLogin(enabled)
        } catch {
            maintenanceMessage = "launch at login: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    func openEventsLog() {
        guard FileManager.default.fileExists(atPath: paths.eventsURL.path) else {
            maintenanceMessage = "no events.log yet at \(paths.eventsURL.path)"
            return
        }
        NSWorkspace.shared.open(paths.eventsURL)
    }

    func repairServices() {
        maintenanceMessage = "re-registering services…"
        Task {
            let registrar = registrar
            let lines = await Task.detached(priority: .userInitiated) { registrar.repair() }.value
            maintenanceMessage = lines.joined(separator: "\n")
        }
    }

    func uninstall() {
        maintenanceMessage = "uninstalling…"
        Task {
            let lines = await Uninstaller.run(registrar: registrar, commands: commands)
            maintenanceMessage = lines.joined(separator: "\n")
            resetFirstRun()
        }
    }

    // MARK: - First run

    func completeFirstRun() {
        firstRunCompleted = true
        UserDefaults.standard.set(true, forKey: Self.firstRunCompletedKey)
    }

    private func resetFirstRun() {
        firstRunCompleted = false
        UserDefaults.standard.set(false, forKey: Self.firstRunCompletedKey)
    }
}
