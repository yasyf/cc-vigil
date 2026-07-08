import CCVigilShared
import Foundation
import Testing

private func entry(path: String, mtime: Int64) -> TranscriptFileEntry {
    TranscriptFileEntry(path: path, mtime: Date(timeIntervalSince1970: TimeInterval(mtime)), size: 1)
}

@Test func windowIsMaxOfActivityAndPendingAsyncPlusMargin() throws {
    #expect(TranscriptDiscoveryPolicy.windowSeconds(config: .default) == 43200 + 3600)
    let wideActivity = try VigilConfig(
        activityWindowSeconds: 100_000,
        pendingAsyncMaxAgeSeconds: 500
    )
    #expect(TranscriptDiscoveryPolicy.windowSeconds(config: wideActivity) == 100_000 + 3600)
}

@Test func selectKeepsEntriesInsideTheWindowSortedByPath() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let window = Int64(TranscriptDiscoveryPolicy.windowSeconds(config: .default))
    let selected = TranscriptDiscoveryPolicy.select(
        entries: [
            entry(path: "/t/b.jsonl", mtime: 1_000_000 - window),
            entry(path: "/t/a.jsonl", mtime: 999_999),
            entry(path: "/t/old.jsonl", mtime: 1_000_000 - window - 1),
        ],
        config: .default,
        now: now
    )
    #expect(selected.map(\.path) == ["/t/a.jsonl", "/t/b.jsonl"])
}
