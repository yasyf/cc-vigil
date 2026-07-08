import CCVigilAppKit
import CCVigilShared
import Foundation
import Observation

/// Executes the InstallerStateMachine's effects at the edges: SMAppService,
/// the bundled CLI, and the symlink filesystem.
@MainActor
@Observable
final class InstallerController {
    private(set) var state: InstallerState = .idle

    @ObservationIgnored private var machine = InstallerStateMachine()
    @ObservationIgnored private let registrar = ServiceRegistrar()
    @ObservationIgnored private let onCompleted: @MainActor () -> Void

    init(onCompleted: @escaping @MainActor () -> Void) {
        self.onCompleted = onCompleted
    }

    func begin() {
        send(.begin(translocated: Bundle.main.bundlePath.contains("/AppTranslocation/")))
    }

    func retry() {
        send(.retry)
    }

    func openLoginItemsSettings() {
        registrar.openLoginItemsSettings()
    }

    private func send(_ event: InstallerEvent) {
        let effects = machine.handle(event)
        state = machine.state
        if case .done = state {
            onCompleted()
        }
        for effect in effects {
            perform(effect)
        }
    }

    private func perform(_ effect: InstallerEffect) {
        switch effect {
        case let .register(service):
            run { [registrar] in .registration(service, registrar.register(service)) }
        case let .reregister(service):
            run { [registrar] in .registration(service, registrar.reregister(service)) }
        case .checkServiceStatuses:
            run { [registrar] in .statuses(registrar.statuses()) }
        case .openLoginItemsSettings:
            registrar.openLoginItemsSettings()
        case .scheduleStatusPoll:
            run { [registrar] in
                try? await Task.sleep(for: .seconds(InstallerStateMachine.statusPollSeconds))
                return .statuses(registrar.statuses())
            }
        case .installHooks:
            let command = HookInstaller.command(cliPath: Self.resolvedCLIPath)
            run {
                let result = await BundledCLI.run(["install-hooks"])
                return .hooks(result.status == 0 ? .installed(command: command) : .failed(result.output))
            }
        case .linkCLI:
            let cliPath = Self.resolvedCLIPath
            run {
                .symlink(CLISymlinker.link(
                    cliPath: cliPath,
                    directories: CLISymlinker.defaultDirectories(
                        home: FileManager.default.homeDirectoryForCurrentUser
                    ),
                    fileSystem: SystemSymlinkFileSystem()
                ))
            }
        }
    }

    private static var resolvedCLIPath: String {
        BundledCLI.url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func run(_ work: @escaping @Sendable () async -> InstallerEvent) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let event = await work()
            await self?.send(event)
        }
    }
}
