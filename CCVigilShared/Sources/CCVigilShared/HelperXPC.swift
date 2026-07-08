import Foundation

public enum HelperXPC {
    public static let machServiceName = "dev.yasyf.cc-vigil.helper"
    public static let daemonIdentifier = "dev.yasyf.cc-vigil.daemon"
    public static let errorDomain = "dev.yasyf.cc-vigil.helper"
}

@objc public protocol HelperXPCProtocol {
    func setSleepBlocked(_ blocked: Bool, reply: @escaping @Sendable (Bool, NSError?) -> Void)
    func sleepBlockedState(reply: @escaping @Sendable (Bool) -> Void)
    func version(reply: @escaping @Sendable (String) -> Void)
}
