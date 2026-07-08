import CCVigilAppKit
import Testing

private func machineAtAwaitingApproval(openedSettings: Bool = false) -> InstallerStateMachine {
    var machine = InstallerStateMachine()
    _ = machine.handle(.begin(translocated: false))
    _ = machine.handle(.registration(.daemonAgent, .registered))
    _ = machine.handle(.registration(.helperDaemon, .registered))
    if openedSettings {
        _ = machine.handle(.statuses([.daemonAgent: .requiresApproval, .helperDaemon: .requiresApproval]))
    }
    return machine
}

private func machineAtInstallingHooks() -> InstallerStateMachine {
    var machine = machineAtAwaitingApproval()
    _ = machine.handle(.statuses([.daemonAgent: .enabled, .helperDaemon: .enabled]))
    return machine
}

@Test func beginTranslocatedBlocks() {
    var machine = InstallerStateMachine()
    let effects = machine.handle(.begin(translocated: true))
    #expect(effects == [])
    #expect(machine.state == .translocated)
}

@Test func beginAfterMoveRestartsFromTranslocated() {
    var machine = InstallerStateMachine()
    _ = machine.handle(.begin(translocated: true))
    let effects = machine.handle(.begin(translocated: false))
    #expect(effects == [.register(.daemonAgent), .register(.helperDaemon)])
    #expect(machine.state == .registeringServices(pending: [.daemonAgent, .helperDaemon], remediated: []))
}

@Test func happyPathReachesDone() {
    var machine = InstallerStateMachine()
    #expect(machine.handle(.begin(translocated: false)) == [
        .register(.daemonAgent),
        .register(.helperDaemon),
    ])
    #expect(machine.handle(.registration(.daemonAgent, .registered)) == [])
    #expect(machine.state == .registeringServices(pending: [.helperDaemon], remediated: []))
    #expect(machine.handle(.registration(.helperDaemon, .registered)) == [.checkServiceStatuses])
    #expect(machine.state == .awaitingApproval(openedSettings: false))
    #expect(machine.handle(.statuses([.daemonAgent: .enabled, .helperDaemon: .enabled])) == [.installHooks])
    #expect(machine.state == .installingHooks)
    let command = "/Applications/CCVigil.app/Contents/Helpers/cc-vigil nudge"
    #expect(machine.handle(.hooks(.installed(command: command))) == [.linkCLI])
    #expect(machine.state == .linkingCLI(hookCommand: command))
    #expect(machine.handle(.symlink(.linked(path: "/usr/local/bin/cc-vigil"))) == [])
    #expect(machine.state == .done(InstallSummary(
        hookCommand: command,
        cliSymlinkPath: "/usr/local/bin/cc-vigil"
    )))
}

@Test func notPermittedRemediatesExactlyOnce() {
    var machine = InstallerStateMachine()
    _ = machine.handle(.begin(translocated: false))
    #expect(machine.handle(.registration(.helperDaemon, .notPermitted)) == [.reregister(.helperDaemon)])
    #expect(machine.state == .registeringServices(
        pending: [.daemonAgent, .helperDaemon],
        remediated: [.helperDaemon]
    ))
    let effects = machine.handle(.registration(.helperDaemon, .notPermitted))
    #expect(effects == [])
    #expect(machine.state == .failed(
        step: .services,
        message: "dev.yasyf.cc-vigil.helper.plist still not permitted after re-registering"
    ))
}

@Test func remediatedRegistrationStillCompletes() {
    var machine = InstallerStateMachine()
    _ = machine.handle(.begin(translocated: false))
    _ = machine.handle(.registration(.daemonAgent, .registered))
    _ = machine.handle(.registration(.helperDaemon, .notPermitted))
    #expect(machine.handle(.registration(.helperDaemon, .registered)) == [.checkServiceStatuses])
    #expect(machine.state == .awaitingApproval(openedSettings: false))
}

@Test func registrationFailureCarriesServiceAndMessage() {
    var machine = InstallerStateMachine()
    _ = machine.handle(.begin(translocated: false))
    _ = machine.handle(.registration(.daemonAgent, .failed("codesign rejected")))
    #expect(machine.state == .failed(
        step: .services,
        message: "dev.yasyf.cc-vigil.daemon.plist: codesign rejected"
    ))
}

@Test func requiresApprovalOpensSettingsOnlyOnce() {
    var machine = machineAtAwaitingApproval()
    let first = machine.handle(.statuses([.daemonAgent: .enabled, .helperDaemon: .requiresApproval]))
    #expect(first == [.openLoginItemsSettings, .scheduleStatusPoll])
    #expect(machine.state == .awaitingApproval(openedSettings: true))
    let second = machine.handle(.statuses([.daemonAgent: .enabled, .helperDaemon: .requiresApproval]))
    #expect(second == [.scheduleStatusPoll])
    #expect(machine.state == .awaitingApproval(openedSettings: true))
}

@Test func approvalAdvancesWhenBothEnabled() {
    var machine = machineAtAwaitingApproval(openedSettings: true)
    let effects = machine.handle(.statuses([.daemonAgent: .enabled, .helperDaemon: .enabled]))
    #expect(effects == [.installHooks])
    #expect(machine.state == .installingHooks)
}

@Test func notFoundStatusFails() {
    var machine = machineAtAwaitingApproval()
    _ = machine.handle(.statuses([.daemonAgent: .notFound, .helperDaemon: .enabled]))
    #expect(machine.state == .failed(
        step: .approval,
        message: "dev.yasyf.cc-vigil.daemon.plist not found by launchd"
    ))
}

@Test func hooksFailureFailsAndRetryRerunsHooks() {
    var machine = machineAtInstallingHooks()
    _ = machine.handle(.hooks(.failed("settings unparseable")))
    #expect(machine.state == .failed(step: .hooks, message: "settings unparseable"))
    let effects = machine.handle(.retry)
    #expect(effects == [.installHooks])
    #expect(machine.state == .installingHooks)
}

@Test func symlinkFailureRetriesFromHooks() {
    var machine = machineAtInstallingHooks()
    _ = machine.handle(.hooks(.installed(command: "cli nudge")))
    _ = machine.handle(.symlink(.failed("permission denied")))
    #expect(machine.state == .failed(step: .symlink, message: "permission denied"))
    #expect(machine.handle(.retry) == [.installHooks])
    #expect(machine.state == .installingHooks)
}

@Test func serviceFailureRetryRestartsRegistration() {
    var machine = InstallerStateMachine()
    _ = machine.handle(.begin(translocated: false))
    _ = machine.handle(.registration(.daemonAgent, .failed("boom")))
    let effects = machine.handle(.retry)
    #expect(effects == [.register(.daemonAgent), .register(.helperDaemon)])
    #expect(machine.state == .registeringServices(pending: [.daemonAgent, .helperDaemon], remediated: []))
}

@Test func staleEventsAreIgnored() {
    var machine = machineAtInstallingHooks()
    let before = machine.state
    #expect(machine.handle(.statuses([.daemonAgent: .enabled, .helperDaemon: .enabled])) == [])
    #expect(machine.handle(.registration(.daemonAgent, .registered)) == [])
    #expect(machine.handle(.symlink(.linked(path: "/usr/local/bin/cc-vigil"))) == [])
    #expect(machine.handle(.retry) == [])
    #expect(machine.state == before)
}
