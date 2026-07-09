import Foundation

extension NSXPCConnection {
    // WORKAROUND: -[NSXPCConnection auditToken] is SPI with no public equivalent;
    // read it via KVC and fail closed (reject the peer) if the shape ever changes.
    var auditTokenData: Data? {
        guard let data = value(forKey: "auditToken") as? Data,
              data.count == MemoryLayout<audit_token_t>.size
        else {
            return nil
        }
        return data
    }
}
