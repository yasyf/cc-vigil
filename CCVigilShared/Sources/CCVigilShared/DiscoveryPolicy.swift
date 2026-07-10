import Foundation

public struct TranscriptFileEntry: Equatable, Sendable {
    public let path: String
    public let mtime: Date
    public let size: Int64
    public let fileID: UInt64

    public init(path: String, mtime: Date, size: Int64, fileID: UInt64) {
        self.path = path
        self.mtime = mtime
        self.size = size
        self.fileID = fileID
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
        now: Date,
        pinnedSessionIDs: Set<String>
    ) -> [TranscriptFileEntry] {
        let cutoff = now.addingTimeInterval(-TimeInterval(windowSeconds(config: config)))
        return entries
            .filter { $0.mtime >= cutoff || pinnedSessionIDs.contains(sessionStem(of: $0.path)) }
            .sorted { $0.path < $1.path }
    }

    private static func sessionStem(of path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}
