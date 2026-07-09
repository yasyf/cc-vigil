import Foundation

/// Tracks the transcript roots the daemon scans and admits a nudge-carried root
/// only when its real path is not already covered. Real-path resolution is I/O
/// and happens at the daemon edge; this core is a pure dedupe over resolved
/// paths. `registeredRoots` holds the dynamically discovered raw paths that are
/// persisted so they survive a restart.
public struct TranscriptRootRegistry: Equatable, Sendable {
    public private(set) var registeredRoots: [String]
    private var knownRealPaths: Set<String>

    public init(knownRealPaths: Set<String>, registeredRoots: [String]) {
        self.knownRealPaths = knownRealPaths
        self.registeredRoots = registeredRoots
    }

    /// Records a newly discovered root. Returns `true` when `realPath` was not
    /// already covered, in which case `rawPath` joins `registeredRoots`.
    public mutating func register(rawPath: String, realPath: String) -> Bool {
        guard knownRealPaths.insert(realPath).inserted else { return false }
        registeredRoots.append(rawPath)
        return true
    }
}
