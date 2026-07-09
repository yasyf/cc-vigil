import Foundation

public enum AppXPC {
    public static let machServiceName = "dev.yasyf.cc-vigil.daemon"
    public static let appIdentifier = "dev.yasyf.cc-vigil"
}

@objc public protocol AppXPCProtocol {
    func subscribe(reply: @escaping @Sendable (Data) -> Void)
}

@objc public protocol AppXPCClientProtocol {
    func statusChanged(_ statusJSON: Data)
}
