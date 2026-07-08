import Foundation

public protocol CodeSignatureChecking: Sendable {
    func selfTeamIdentifier() -> String?
    func callerSatisfies(requirement: String, auditToken: Data) -> Bool
    func callerSigningIdentifier(auditToken: Data) -> String?
}

/// Gates XPC peers of the root helper. Team-signed builds enforce the strong
/// requirement (identifier + anchor + team OU). The identifier-only fallback is
/// the ad-hoc/dev signing path — it MUST stay off in Release
/// (`allowIdentifierOnlyFallback == false`) so a Release build whose team-id
/// read unexpectedly returns nil fails closed instead of accepting a peer by
/// signing identifier alone.
public struct CallerVerifier: Sendable {
    private let clientIdentifier: String
    private let checker: any CodeSignatureChecking
    private let allowIdentifierOnlyFallback: Bool

    public init(
        clientIdentifier: String,
        checker: any CodeSignatureChecking,
        allowIdentifierOnlyFallback: Bool
    ) {
        self.clientIdentifier = clientIdentifier
        self.checker = checker
        self.allowIdentifierOnlyFallback = allowIdentifierOnlyFallback
    }

    public func requirement(teamIdentifier: String) -> String {
        "identifier \"\(clientIdentifier)\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    public func shouldAccept(auditToken: Data?) -> Bool {
        guard let auditToken else { return false }
        guard let teamIdentifier = checker.selfTeamIdentifier() else {
            guard allowIdentifierOnlyFallback else { return false }
            return checker.callerSigningIdentifier(auditToken: auditToken) == clientIdentifier
        }
        return checker.callerSatisfies(
            requirement: requirement(teamIdentifier: teamIdentifier),
            auditToken: auditToken
        )
    }
}
