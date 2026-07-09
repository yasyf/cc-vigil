import CCVigilShared
import Foundation

public struct TranscriptScanner: Sendable {
    public let roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots
    }

    public func entries() -> [TranscriptFileEntry] {
        let fileManager = FileManager.default
        var byRealPath: [String: TranscriptFileEntry] = [:]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: nil
            ) else { continue }
            let rootDepth = root.resolvingSymlinksInPath().pathComponents.count
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                let resolved = url.resolvingSymlinksInPath()
                // Subagent sidechains (<session>/subagents/agent-*.jsonl) never open a
                // turn on their own; the parent transcript carries the authoritative
                // pending-async state with a real completion marker. Test the exclusion
                // on the resolved path relative to the resolved root, so neither a
                // "subagents" ancestor of the root nor a symlink resolving into a
                // sidechain directory can shadow or smuggle in a transcript.
                let interior = resolved.pathComponents.dropFirst(rootDepth).dropLast()
                guard !interior.contains("subagents") else { continue }
                // One real path keyed once dedupes both a within-root symlink and
                // a symlinked overlap between two roots.
                let realPath = resolved.path
                guard byRealPath[realPath] == nil else { continue }
                // A transcript can vanish between listing and stat; skip it.
                guard let attributes = try? fileManager.attributesOfItem(atPath: realPath),
                      let mtime = attributes[.modificationDate] as? Date,
                      let size = (attributes[.size] as? NSNumber)?.int64Value,
                      let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
                else { continue }
                byRealPath[realPath] = TranscriptFileEntry(path: realPath, mtime: mtime, size: size, fileID: fileID)
            }
        }
        return Array(byRealPath.values)
    }
}
