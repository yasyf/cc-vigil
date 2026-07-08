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
        var byRealPath: [String: TranscriptFileEntry] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let realPath = url.resolvingSymlinksInPath().path
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
