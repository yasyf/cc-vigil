import CCVigilShared
import Foundation
import Security

struct SecCodeChecker: CodeSignatureChecking {
    func selfTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        return signingInfo(of: code)?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    func callerSatisfies(requirement: String, auditToken: Data) -> Bool {
        guard let code = guestCode(auditToken: auditToken) else {
            return false
        }
        var compiled: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess,
              let compiled
        else {
            return false
        }
        return SecCodeCheckValidity(code, [], compiled) == errSecSuccess
    }

    func callerSigningIdentifier(auditToken: Data) -> String? {
        guard let code = guestCode(auditToken: auditToken),
              SecCodeCheckValidity(code, [], nil) == errSecSuccess
        else {
            return nil
        }
        return signingInfo(of: code)?[kSecCodeInfoIdentifier as String] as? String
    }

    private func guestCode(auditToken: Data) -> SecCode? {
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: auditToken] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else {
            return nil
        }
        return code
    }

    private func signingInfo(of code: SecCode) -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess else {
            return nil
        }
        return info as? [String: Any]
    }
}
