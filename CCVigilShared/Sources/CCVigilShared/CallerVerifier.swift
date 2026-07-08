import Foundation

public protocol CodeSignatureChecking: Sendable {
    func selfTeamIdentifier() -> String?
    func callerSatisfies(requirement: String, auditToken: Data) -> Bool
    func callerSigningIdentifier(auditToken: Data) -> String?
}

public struct CallerVerifier: Sendable {
    private let clientIdentifier: String
    private let checker: any CodeSignatureChecking

    public init(clientIdentifier: String, checker: any CodeSignatureChecking) {
        self.clientIdentifier = clientIdentifier
        self.checker = checker
    }

    public func requirement(teamIdentifier: String) -> String {
        "identifier \"\(clientIdentifier)\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    public func shouldAccept(auditToken: Data?) -> Bool {
        guard let auditToken else { return false }
        guard let teamIdentifier = checker.selfTeamIdentifier() else {
            return checker.callerSigningIdentifier(auditToken: auditToken) == clientIdentifier
        }
        return checker.callerSatisfies(
            requirement: requirement(teamIdentifier: teamIdentifier),
            auditToken: auditToken
        )
    }
}
