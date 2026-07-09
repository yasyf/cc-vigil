import CCVigilShared
import Foundation
import Testing

private let auditToken = Data(repeating: 7, count: 32)

private final class FakeCodeSignatureChecker: CodeSignatureChecking, @unchecked Sendable {
    private let selfTeam: String?
    private let requirementSatisfied: Bool
    private let callerIdentifier: String?
    private(set) var requirementsEvaluated: [String] = []
    private(set) var identifierLookups = 0

    init(selfTeam: String?, requirementSatisfied: Bool = false, callerIdentifier: String? = nil) {
        self.selfTeam = selfTeam
        self.requirementSatisfied = requirementSatisfied
        self.callerIdentifier = callerIdentifier
    }

    func selfTeamIdentifier() -> String? {
        selfTeam
    }

    func callerSatisfies(requirement: String, auditToken _: Data) -> Bool {
        requirementsEvaluated.append(requirement)
        return requirementSatisfied
    }

    func callerSigningIdentifier(auditToken _: Data) -> String? {
        identifierLookups += 1
        return callerIdentifier
    }
}

@Test func verifierFailsClosedOnMissingAuditToken() {
    let checker = FakeCodeSignatureChecker(
        selfTeam: "TEAM123",
        requirementSatisfied: true,
        callerIdentifier: HelperXPC.daemonIdentifier
    )
    let verifier = CallerVerifier(
        clientIdentifier: HelperXPC.daemonIdentifier,
        checker: checker,
        allowIdentifierOnlyFallback: true
    )
    #expect(verifier.shouldAccept(auditToken: nil) == false)
    #expect(checker.requirementsEvaluated.isEmpty)
    #expect(checker.identifierLookups == 0)
}

@Test func verifierAcceptsTeamPinnedCallerWithExactRequirement() {
    let checker = FakeCodeSignatureChecker(selfTeam: "TEAM123", requirementSatisfied: true)
    let verifier = CallerVerifier(
        clientIdentifier: "dev.yasyf.cc-vigil.daemon",
        checker: checker,
        allowIdentifierOnlyFallback: true
    )
    #expect(verifier.shouldAccept(auditToken: auditToken) == true)
    #expect(checker.requirementsEvaluated == [
        "identifier \"dev.yasyf.cc-vigil.daemon\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"TEAM123\"",
    ])
    #expect(checker.identifierLookups == 0)
}

@Test func verifierAcceptsTeamPinnedAppClientForDaemonListener() {
    let checker = FakeCodeSignatureChecker(selfTeam: "TEAM123", requirementSatisfied: true)
    let verifier = CallerVerifier(
        clientIdentifier: AppXPC.appIdentifier,
        checker: checker,
        allowIdentifierOnlyFallback: false
    )
    #expect(verifier.shouldAccept(auditToken: auditToken) == true)
    #expect(checker.requirementsEvaluated == [
        "identifier \"dev.yasyf.cc-vigil\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"TEAM123\"",
    ])
    #expect(checker.identifierLookups == 0)
}

@Test func verifierRejectsNonAppDaemonPeerFailingClosedInRelease() {
    let checker = FakeCodeSignatureChecker(
        selfTeam: nil,
        callerIdentifier: HelperXPC.daemonIdentifier
    )
    let verifier = CallerVerifier(
        clientIdentifier: AppXPC.appIdentifier,
        checker: checker,
        allowIdentifierOnlyFallback: false
    )
    #expect(verifier.shouldAccept(auditToken: auditToken) == false)
    #expect(checker.requirementsEvaluated.isEmpty)
    #expect(checker.identifierLookups == 0)
}

@Test func verifierTeamPinnedRejectionNeverFallsBackToNameOnly() {
    let checker = FakeCodeSignatureChecker(
        selfTeam: "TEAM123",
        requirementSatisfied: false,
        callerIdentifier: HelperXPC.daemonIdentifier
    )
    let verifier = CallerVerifier(
        clientIdentifier: HelperXPC.daemonIdentifier,
        checker: checker,
        allowIdentifierOnlyFallback: true
    )
    #expect(verifier.shouldAccept(auditToken: auditToken) == false)
    #expect(checker.requirementsEvaluated.count == 1)
    #expect(checker.identifierLookups == 0)
}

@Test(arguments: [
    ("dev.yasyf.cc-vigil.daemon", true),
    ("dev.yasyf.cc-vigil.daemon2", false),
    ("dev.yasyf.cc-vigil", false),
    (nil, false),
])
func verifierAdHocMatchesSigningIdentifierExactly(callerIdentifier: String?, expected: Bool) {
    let checker = FakeCodeSignatureChecker(selfTeam: nil, callerIdentifier: callerIdentifier)
    let verifier = CallerVerifier(
        clientIdentifier: "dev.yasyf.cc-vigil.daemon",
        checker: checker,
        allowIdentifierOnlyFallback: true
    )
    #expect(verifier.shouldAccept(auditToken: auditToken) == expected)
    #expect(checker.requirementsEvaluated.isEmpty)
    #expect(checker.identifierLookups == 1)
}

@Test func verifierFailsClosedInReleaseWhenTeamIdentifierMissing() {
    let checker = FakeCodeSignatureChecker(selfTeam: nil, callerIdentifier: HelperXPC.daemonIdentifier)
    let verifier = CallerVerifier(
        clientIdentifier: HelperXPC.daemonIdentifier,
        checker: checker,
        allowIdentifierOnlyFallback: false
    )
    #expect(verifier.shouldAccept(auditToken: auditToken) == false)
    #expect(checker.requirementsEvaluated.isEmpty)
    #expect(checker.identifierLookups == 0)
}
