import CCVigilShared
import Foundation

public struct TranscriptScanner: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func entries() -> [TranscriptFileEntry] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }
        let rootDepth = root.resolvingSymlinksInPath().pathComponents.count
        var byRealPath: [String: TranscriptFileEntry] = [:]
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
        return Array(byRealPath.values)
    }
}
