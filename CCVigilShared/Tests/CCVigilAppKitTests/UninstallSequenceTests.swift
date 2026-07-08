import CCVigilAppKit
import Testing

private actor CallLog {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

@Test func uninstallClearsSleepBlockBeforeUnregistering() async {
    let log = CallLog()
    let steps = UninstallSteps(
        uninstallHooks: { await log.record("hooks"); return "removed hooks" },
        clearSleepBlock: { await log.record("clear"); return true },
        unregisterServices: {
            await log.record("unregister")
            return ["unregistered daemon", "unregistered helper"]
        },
        removeSymlinks: { await log.record("symlinks"); return "removed /usr/local/bin/cc-vigil" }
    )
    let lines = await UninstallSequence.run(steps)
    #expect(await log.events == ["hooks", "clear", "unregister", "symlinks"])
    #expect(lines == [
        "removed hooks",
        "cleared the sleep block",
        "unregistered daemon",
        "unregistered helper",
        "removed /usr/local/bin/cc-vigil",
    ])
}

@Test func uninstallProceedsWhenClearCannotBeConfirmed() async {
    let log = CallLog()
    let steps = UninstallSteps(
        uninstallHooks: { "removed hooks" },
        clearSleepBlock: { await log.record("clear"); return false },
        unregisterServices: { await log.record("unregister"); return ["unregistered daemon"] },
        removeSymlinks: { "no CLI symlink to remove" }
    )
    let lines = await UninstallSequence.run(steps)
    #expect(await log.events == ["clear", "unregister"])
    #expect(lines == [
        "removed hooks",
        "sleep block clear unconfirmed; shutdown handlers will retry",
        "unregistered daemon",
        "no CLI symlink to remove",
    ])
}
