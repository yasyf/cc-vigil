import Foundation

public enum AppStatusSubscription {
    /// Resolves a status snapshot (nil means "nothing published yet") to the
    /// bytes handed to the XPC subscribe reply, which must fire exactly once so
    /// a subscribing client is never left awaiting a callback.
    public static func deliver(snapshot: Data?, reply: (Data) -> Void) {
        reply(snapshot ?? Data())
    }
}
