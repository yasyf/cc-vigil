import Foundation

public enum ManagedService: String, CaseIterable, Equatable, Sendable {
    case daemonAgent = "dev.yasyf.cc-vigil.daemon.plist"
    case helperDaemon = "dev.yasyf.cc-vigil.helper.plist"
}

public enum ServiceStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public enum RegistrationOutcome: Equatable, Sendable {
    case registered
    case notPermitted
    case failed(String)
}

public enum HooksOutcome: Equatable, Sendable {
    case installed(command: String)
    case failed(String)
}

public enum SymlinkOutcome: Equatable, Sendable {
    case linked(path: String)
    case failed(String)
}

public enum InstallerStep: String, Equatable, Sendable {
    case services
    case approval
    case hooks
    case symlink
}

public struct InstallSummary: Equatable, Sendable {
    public let hookCommand: String
    public let cliSymlinkPath: String

    public init(hookCommand: String, cliSymlinkPath: String) {
        self.hookCommand = hookCommand
        self.cliSymlinkPath = cliSymlinkPath
    }
}

public enum InstallerEffect: Equatable, Sendable {
    case register(ManagedService)
    case reregister(ManagedService)
    case checkServiceStatuses
    case openLoginItemsSettings
    case scheduleStatusPoll
    case installHooks
    case linkCLI
}

public enum InstallerEvent: Equatable, Sendable {
    case begin(translocated: Bool)
    case registration(ManagedService, RegistrationOutcome)
    case statuses([ManagedService: ServiceStatus])
    case hooks(HooksOutcome)
    case symlink(SymlinkOutcome)
    case retry
}

public enum InstallerState: Equatable, Sendable {
    case idle
    case translocated
    case registeringServices(pending: Set<ManagedService>, remediated: Set<ManagedService>)
    case awaitingApproval(openedSettings: Bool)
    case installingHooks
    case linkingCLI(hookCommand: String)
    case failed(step: InstallerStep, message: String)
    case done(InstallSummary)
}

public struct InstallerStateMachine: Equatable, Sendable {
    public static let statusPollSeconds = 2.0

    public private(set) var state: InstallerState = .idle

    public init() {}

    public mutating func handle(_ event: InstallerEvent) -> [InstallerEffect] {
        switch (state, event) {
        case let (_, .begin(translocated)):
            guard !translocated else {
                state = .translocated
                return []
            }
            return startRegistration()
        case let (.registeringServices(pending, remediated), .registration(service, outcome)):
            return handleRegistration(service, outcome, pending: pending, remediated: remediated)
        case let (.awaitingApproval(openedSettings), .statuses(statuses)):
            return handleStatuses(statuses, openedSettings: openedSettings)
        case let (.installingHooks, .hooks(outcome)):
            return handleHooks(outcome)
        case let (.linkingCLI(hookCommand), .symlink(outcome)):
            return handleSymlink(outcome, hookCommand: hookCommand)
        case let (.failed(step, _), .retry):
            return retryFrom(step)
        default:
            // A stale async result (poll tick, registration reply) landing
            // after the state moved on carries no work.
            return []
        }
    }

    private mutating func startRegistration() -> [InstallerEffect] {
        state = .registeringServices(pending: Set(ManagedService.allCases), remediated: [])
        return ManagedService.allCases.map { .register($0) }
    }

    private mutating func handleRegistration(
        _ service: ManagedService,
        _ outcome: RegistrationOutcome,
        pending: Set<ManagedService>,
        remediated: Set<ManagedService>
    ) -> [InstallerEffect] {
        switch outcome {
        case .registered:
            let remaining = pending.subtracting([service])
            guard remaining.isEmpty else {
                state = .registeringServices(pending: remaining, remediated: remediated)
                return []
            }
            state = .awaitingApproval(openedSettings: false)
            return [.checkServiceStatuses]
        case .notPermitted:
            guard !remediated.contains(service) else {
                state = .failed(
                    step: .services,
                    message: "\(service.rawValue) still not permitted after re-registering"
                )
                return []
            }
            state = .registeringServices(pending: pending, remediated: remediated.union([service]))
            return [.reregister(service)]
        case let .failed(message):
            state = .failed(step: .services, message: "\(service.rawValue): \(message)")
            return []
        }
    }

    private mutating func handleStatuses(
        _ statuses: [ManagedService: ServiceStatus],
        openedSettings: Bool
    ) -> [InstallerEffect] {
        if let missing = ManagedService.allCases.first(where: { statuses[$0] == .notFound }) {
            state = .failed(step: .approval, message: "\(missing.rawValue) not found by launchd")
            return []
        }
        guard ManagedService.allCases.allSatisfy({ statuses[$0] == .enabled }) else {
            let effects: [InstallerEffect] = openedSettings
                ? [.scheduleStatusPoll]
                : [.openLoginItemsSettings, .scheduleStatusPoll]
            state = .awaitingApproval(openedSettings: true)
            return effects
        }
        state = .installingHooks
        return [.installHooks]
    }

    private mutating func handleHooks(_ outcome: HooksOutcome) -> [InstallerEffect] {
        switch outcome {
        case let .installed(command):
            state = .linkingCLI(hookCommand: command)
            return [.linkCLI]
        case let .failed(message):
            state = .failed(step: .hooks, message: message)
            return []
        }
    }

    private mutating func handleSymlink(
        _ outcome: SymlinkOutcome,
        hookCommand: String
    ) -> [InstallerEffect] {
        switch outcome {
        case let .linked(path):
            state = .done(InstallSummary(hookCommand: hookCommand, cliSymlinkPath: path))
            return []
        case let .failed(message):
            state = .failed(step: .symlink, message: message)
            return []
        }
    }

    private mutating func retryFrom(_ step: InstallerStep) -> [InstallerEffect] {
        switch step {
        case .services, .approval:
            return startRegistration()
        case .hooks, .symlink:
            // Hook install repairs in place, so a symlink retry safely re-runs it.
            state = .installingHooks
            return [.installHooks]
        }
    }
}
