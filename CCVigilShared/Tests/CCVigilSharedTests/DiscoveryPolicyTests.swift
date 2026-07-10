import CCVigilShared
import Foundation
import Testing

private func entry(path: String, mtime: Int64) -> TranscriptFileEntry {
    TranscriptFileEntry(path: path, mtime: Date(timeIntervalSince1970: TimeInterval(mtime)), size: 1, fileID: 1)
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
        now: now,
        pinnedSessionIDs: []
    )
    #expect(selected.map(\.path) == ["/t/a.jsonl", "/t/b.jsonl"])
}

@Test func pinnedSessionOutsideTheWindowIsKept() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let window = Int64(TranscriptDiscoveryPolicy.windowSeconds(config: .default))
    let selected = TranscriptDiscoveryPolicy.select(
        entries: [entry(path: "/t/pinned.jsonl", mtime: 1_000_000 - window - 5000)],
        config: .default,
        now: now,
        pinnedSessionIDs: ["pinned"]
    )
    #expect(selected.map(\.path) == ["/t/pinned.jsonl"])
}

@Test func unpinnedSessionOutsideTheWindowIsDropped() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let window = Int64(TranscriptDiscoveryPolicy.windowSeconds(config: .default))
    let selected = TranscriptDiscoveryPolicy.select(
        entries: [entry(path: "/t/other.jsonl", mtime: 1_000_000 - window - 5000)],
        config: .default,
        now: now,
        pinnedSessionIDs: ["pinned"]
    )
    #expect(selected.isEmpty)
}

@Test func emptyPinnedSetLeavesWindowBehaviorUnchanged() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let window = Int64(TranscriptDiscoveryPolicy.windowSeconds(config: .default))
    let selected = TranscriptDiscoveryPolicy.select(
        entries: [
            entry(path: "/t/b.jsonl", mtime: 1_000_000 - window),
            entry(path: "/t/a.jsonl", mtime: 999_999),
            entry(path: "/t/old.jsonl", mtime: 1_000_000 - window - 1),
        ],
        config: .default,
        now: now,
        pinnedSessionIDs: []
    )
    #expect(selected.map(\.path) == ["/t/a.jsonl", "/t/b.jsonl"])
}

/// The pin is a union with the mtime window, not a replacement: an in-window
/// file and a stale-but-pinned file both survive, sorted by path, while a stale
/// unpinned file is still dropped.
@Test func pinUnionsWithTheWindowAndDropsUnpinnedStale() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let window = Int64(TranscriptDiscoveryPolicy.windowSeconds(config: .default))
    let selected = TranscriptDiscoveryPolicy.select(
        entries: [
            entry(path: "/t/fresh.jsonl", mtime: 999_999),
            entry(path: "/t/pinned-stale.jsonl", mtime: 1_000_000 - window - 9999),
            entry(path: "/t/dead-stale.jsonl", mtime: 1_000_000 - window - 9999),
        ],
        config: .default,
        now: now,
        pinnedSessionIDs: ["pinned-stale"]
    )
    #expect(selected.map(\.path) == ["/t/fresh.jsonl", "/t/pinned-stale.jsonl"])
}

/// The daemon wiring in one line through the pure parts: a nudge carrying a live
/// pid pins its session, and discovery then keeps that session's transcript even
/// after its mtime falls outside the window — the seam that stops a live-but-stale
/// session from being dropped before the oracle ever probes it.
@Test func liveNudgedSessionPinsItsStaleTranscriptThroughDiscovery() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let window = Int64(TranscriptDiscoveryPolicy.windowSeconds(config: .default))
    var tracker = SessionPidTracker()
    tracker.apply(
        NudgePayload(sessionId: "live-session", hookEvent: "Notification", claudePid: 4242),
        now: now
    )
    let pinned = tracker.liveSessionIDs { queried in
        #expect(queried == 4242)
        return Int64(now.timeIntervalSince1970) - 10
    }
    #expect(pinned == ["live-session"])

    let selected = TranscriptDiscoveryPolicy.select(
        entries: [
            entry(path: "/p/live-session.jsonl", mtime: 1_000_000 - window - 4000),
            entry(path: "/p/dead-session.jsonl", mtime: 1_000_000 - window - 4000),
        ],
        config: .default,
        now: now,
        pinnedSessionIDs: pinned
    )
    #expect(selected.map(\.path) == ["/p/live-session.jsonl"])
}
