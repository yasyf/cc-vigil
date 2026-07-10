import CCVigilDaemonKit
import CCVigilShared
import Darwin
import Dispatch
import Foundation
import os

// Only ad-hoc/dev daemon builds (the Debug config sets CCVIGIL_ADHOC_DAEMON_AUTH
// in project.yml) may accept the app by signing identifier alone. Release never
// sets the flag, so a Release build whose team-id read returns nil fails closed.
#if CCVIGIL_ADHOC_DAEMON_AUTH
    private let allowIdentifierOnlyFallback = true
#else
    private let allowIdentifierOnlyFallback = false
#endif

@main
enum DaemonMain {
    static func main() async {
        // Fire-and-forget CLI peers (the nudge hook) close before reading the
        // reply. Per-socket SO_NOSIGPIPE covers the reply write, but a broken
        // peer still trips SIGPIPE on a libdispatch worker that masks it, so the
        // signal is redirected to the main thread and terminates the daemon.
        // Ignoring SIGPIPE process-wide is the standard server hygiene that lets
        // the EPIPE surface at the write instead.
        Darwin.signal(SIGPIPE, SIG_IGN)
        let options = DaemonOptions.parse(
            arguments: Array(CommandLine.arguments.dropFirst()),
            environment: ProcessInfo.processInfo.environment
        )
        let startup = loadStartup(options: options)
        let signal = NudgeSignal()
        let broadcaster = options.dryRun ? nil : StatusBroadcaster()
        let helperClient = HelperClient()
        let pusher: any BlockPushing = options.dryRun ? LogOnlyBlockPusher() : helperClient
        let batterySampler: @Sendable () -> BatteryReading? = if let fakeBatteryFile = options.fakeBatteryFile {
            { FakeBatteryFeed.read(url: fakeBatteryFile) }
        } else {
            { BatteryMonitor.sample() }
        }

        let baseRoots = [options.transcriptsRoot] + startup.config.transcriptsRoots.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let core = DaemonCore(
            config: startup.config,
            clock: SystemClock(),
            transcriptsRoots: baseRoots,
            processLister: SysctlClaudeProcessLister(),
            pusher: pusher,
            helperLink: options.dryRun ? .dryRun : .unknown,
            eventLog: EventLog(url: startup.paths.eventsURL),
            stateURL: startup.paths.stateURL,
            signal: signal,
            broadcaster: broadcaster,
            thermalReader: SMCThermalReader(),
            batterySampler: batterySampler,
            restoredHolds: startup.holds,
            restoredPausedUntil: startup.pausedUntil,
            restoredRegisteredRoots: startup.registeredRoots,
            restoredNextAlertId: startup.nextAlertId,
            restoredRecentAlerts: startup.recentAlerts,
            restoredAlertedCutouts: startup.alertedCutouts
        )
        if !options.dryRun {
            await helperClient.setDisruptionHandler {
                Task { await core.forceReassert() }
            }
        }

        retained = await startServices(
            options: options,
            paths: startup.paths,
            core: core,
            broadcaster: broadcaster,
            pusher: pusher
        )
        await core.recordStarted(version: startup.version, dryRun: options.dryRun)
        Logger.daemon.info(
            "CCVigilDaemon \(startup.version, privacy: .public) started (dryRun=\(options.dryRun, privacy: .public))"
        )

        while true {
            await core.evaluate()
            await signal.wait(upTo: core.pollIntervalSeconds)
        }
    }

    /// The monitors and servers live for the process lifetime; their C
    /// callbacks must never dangle, so they are anchored here.
    @MainActor private static var retained: [AnyObject] = []

    private struct Startup {
        let version: String
        let paths: SupportPaths
        let config: VigilConfig
        let holds: HoldRegistry
        let pausedUntil: Date?
        let registeredRoots: [String]
        let nextAlertId: Int64
        let recentAlerts: [SleepAlert]
        let alertedCutouts: Set<CutoutKind>
    }

    private static func loadStartup(options: DaemonOptions) -> Startup {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            die("CFBundleShortVersionString missing from the embedded Info.plist")
        }
        let paths = SupportPaths(directory: options.supportDirectory)
        do {
            try paths.ensureDirectory()
        } catch {
            die("cannot create support directory \(paths.directory.path): \(error)")
        }
        let config: VigilConfig
        do {
            config = try ConfigLoader.load(url: paths.configURL)
        } catch {
            die("cannot read config file at \(paths.configURL.path): \(error)")
        }
        let restored: PersistedState
        do {
            restored = try StateStore.load(url: paths.stateURL) ?? PersistedState(holds: [], pausedUntil: nil)
        } catch {
            die("cannot read state file at \(paths.stateURL.path): \(error)")
        }
        let holds = HoldRegistry.restored(
            from: restored.holds,
            bootedAt: ProcessFacts.bootedAt(),
            processStart: ProcessFacts.processStart
        )
        let pausedUntil = restored.pausedUntil.flatMap { $0 > Date() ? $0 : nil }
        return Startup(
            version: version,
            paths: paths,
            config: config,
            holds: holds,
            pausedUntil: pausedUntil,
            registeredRoots: restored.registeredRoots,
            nextAlertId: restored.nextAlertId,
            recentAlerts: restored.recentAlerts,
            alertedCutouts: restored.alertedCutouts
        )
    }

    private static func startServices(
        options: DaemonOptions,
        paths: SupportPaths,
        core: DaemonCore,
        broadcaster: StatusBroadcaster?,
        pusher: any BlockPushing
    ) async -> [AnyObject] {
        let socketServer = CLISocketServer(socketPath: paths.socketPath) { request in
            await core.handle(request)
        }
        do {
            try socketServer.start()
        } catch {
            die("CLI socket failed to start at \(paths.socketPath): \(error)")
        }

        let monitorQueue = DispatchQueue(label: "dev.yasyf.cc-vigil.monitors")
        let batterySource: AnyObject
        if let fakeBatteryFile = options.fakeBatteryFile {
            Logger.daemon.error(
                "fake battery seam active (test-only): \(fakeBatteryFile.path, privacy: .public)"
            )
            let feed = FakeBatteryFeed(url: fakeBatteryFile, queue: monitorQueue) { reading in
                Task { await core.updateBattery(reading) }
            }
            feed.start()
            batterySource = feed
        } else {
            let batteryMonitor = BatteryMonitor { reading in
                Task { await core.updateBattery(reading) }
            }
            batteryMonitor.start()
            batterySource = batteryMonitor
        }
        let lidMonitor = LidMonitor(queue: monitorQueue) { closed in
            Task { await core.updateLid(closed: closed) }
        }
        if let lidMonitor {
            await core.updateLid(closed: lidMonitor.current())
        }
        let wakeMonitor = WakeMonitor {
            Task { await core.handleWake() }
        }
        wakeMonitor.start(queue: monitorQueue)

        var services: [AnyObject] = [socketServer, batterySource, wakeMonitor]
        if let lidMonitor {
            services.append(lidMonitor)
        }
        if !options.dryRun, let broadcaster {
            let appServer = AppXPCServer(
                broadcaster: broadcaster,
                verifier: CallerVerifier(
                    clientIdentifier: AppXPC.appIdentifier,
                    checker: SecCodeChecker(),
                    allowIdentifierOnlyFallback: allowIdentifierOnlyFallback
                )
            ) {
                await core.encodedStatus()
            }
            appServer.start()
            services.append(appServer)
        }
        services.append(contentsOf: installTerminationHandlers(core: core, pusher: pusher))
        return services
    }

    /// SIGTERM/SIGINT force a bounded clear before exit: launchd stops the
    /// daemon on logout/unload and the block must never outlive it.
    private static func installTerminationHandlers(
        core: DaemonCore,
        pusher: any BlockPushing
    ) -> [DispatchSourceSignal] {
        let queue = DispatchQueue(label: "dev.yasyf.cc-vigil.signals")
        return [SIGTERM, SIGINT].map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
            source.setEventHandler {
                let done = DispatchSemaphore(value: 0)
                Task {
                    _ = await pusher.push(blocked: false)
                    await core.recordStopped()
                    done.signal()
                }
                _ = done.wait(timeout: .now() + 8)
                exit(0)
            }
            source.resume()
            return source
        }
    }

    private static func die(_ message: String) -> Never {
        Logger.daemon.fault("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("CCVigilDaemon: \(message)\n".utf8))
        exit(78)
    }
}
