import Foundation

public struct TranscriptFileEntry: Equatable, Sendable {
    public let path: String
    public let mtime: Date
    public let size: Int64

    public init(path: String, mtime: Date, size: Int64) {
        self.path = path
        self.mtime = mtime
        self.size = size
    }
}

public enum TranscriptDiscoveryPolicy {
    public static let mtimeMarginSeconds = 3600

    public static func windowSeconds(config: VigilConfig) -> Int {
        max(config.activityWindowSeconds, config.pendingAsyncMaxAgeSeconds) + mtimeMarginSeconds
    }

    public static func select(
        entries: [TranscriptFileEntry],
        config: VigilConfig,
        now: Date
    ) -> [TranscriptFileEntry] {
        let cutoff = now.addingTimeInterval(-TimeInterval(windowSeconds(config: config)))
        return entries
            .filter { $0.mtime >= cutoff }
            .sorted { $0.path < $1.path }
    }
}
