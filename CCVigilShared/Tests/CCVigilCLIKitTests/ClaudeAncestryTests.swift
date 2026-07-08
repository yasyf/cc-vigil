import CCVigilCLIKit
import Testing

private let claudeArgv = ["node", "/usr/local/bin/claude", "--continue"]

@Test func findsNearestClaudeAncestor() {
    let parents: [Int32: Int32] = [500: 400, 400: 300, 300: 1]
    let argvs: [Int32: [String]] = [
        500: ["/bin/zsh", "-c", "cc-vigil nudge"],
        400: ["-zsh"],
        300: claudeArgv,
    ]
    let found = ClaudeAncestry.nearestClaudePid(
        startingAt: 500,
        parent: { parents[$0] },
        argv: { argvs[$0] }
    )
    #expect(found == 300)
}

@Test func matchesTheStartingProcessItself() {
    let found = ClaudeAncestry.nearestClaudePid(
        startingAt: 7,
        parent: { _ in nil },
        argv: { _ in claudeArgv }
    )
    #expect(found == 7)
}

@Test func returnsNilWhenNoClaudeInChain() {
    let parents: [Int32: Int32] = [500: 400, 400: 1]
    let found = ClaudeAncestry.nearestClaudePid(
        startingAt: 500,
        parent: { parents[$0] },
        argv: { _ in ["-zsh"] }
    )
    #expect(found == nil)
}

@Test func survivesArgvHolesInTheChain() {
    let parents: [Int32: Int32] = [500: 400, 400: 300, 300: 1]
    let argvs: [Int32: [String]] = [300: claudeArgv]
    let found = ClaudeAncestry.nearestClaudePid(
        startingAt: 500,
        parent: { parents[$0] },
        argv: { argvs[$0] }
    )
    #expect(found == 300)
}

@Test func stopsOnParentCycles() {
    let found = ClaudeAncestry.nearestClaudePid(
        startingAt: 9,
        parent: { $0 },
        argv: { _ in ["-zsh"] }
    )
    #expect(found == nil)
}

@Test func capsWalkDepth() {
    let found = ClaudeAncestry.nearestClaudePid(
        startingAt: 1000,
        parent: { $0 - 1 },
        argv: { $0 == 900 ? claudeArgv : ["-zsh"] }
    )
    #expect(found == nil)
}
