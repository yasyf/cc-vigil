import CCVigilAppKit
import CCVigilRuntime
import CCVigilShared
import Foundation
import Testing

private func at(_ epoch: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(epoch))
}

private let emptyDecision = BlockDecision(shouldBlock: false, activeSessions: [], discounts: [])

private func edge(_ blocked: Bool, at epoch: Int64) -> EventRecord {
    EventRecord(at: at(epoch), event: .blockEdge(blocked: blocked, applied: blocked, decision: emptyDecision, holds: []))
}

@Test func nothingHappenedYieldsNoLines() {
    let summary = AwayDigest.summarize(records: [], since: at(0), now: at(1000))
    #expect(summary == AwaySummary(blockCount: 0, awakeSeconds: 0, cutouts: []))
    #expect(summary.lines == [])
}

@Test func sumsClosedBlockSegmentsInsideTheWindow() {
    let records = [
        edge(true, at: 1000),
        edge(false, at: 1600),
        edge(true, at: 2000),
        edge(false, at: 2090),
    ]
    let summary = AwayDigest.summarize(records: records, since: at(500), now: at(3000))
    #expect(summary == AwaySummary(blockCount: 2, awakeSeconds: 690, cutouts: []))
    #expect(summary.lines == ["kept awake 11m30s across 2 blocks"])
}

@Test func blockOpenAtWindowStartCountsFromSince() {
    let records = [
        edge(true, at: 100),
        edge(false, at: 1300),
    ]
    let summary = AwayDigest.summarize(records: records, since: at(1000), now: at(2000))
    #expect(summary == AwaySummary(blockCount: 1, awakeSeconds: 300, cutouts: []))
    #expect(summary.lines == ["kept awake 5m across 1 block"])
}

@Test func stillOpenBlockCountsUpToNow() {
    let summary = AwayDigest.summarize(records: [edge(true, at: 1200)], since: at(1000), now: at(1500))
    #expect(summary == AwaySummary(blockCount: 1, awakeSeconds: 300, cutouts: []))
}

@Test func segmentEntirelyBeforeTheWindowIsDropped() {
    let records = [
        edge(true, at: 100),
        edge(false, at: 200),
    ]
    let summary = AwayDigest.summarize(records: records, since: at(1000), now: at(2000))
    #expect(summary == AwaySummary(blockCount: 0, awakeSeconds: 0, cutouts: []))
}

@Test func daemonStopEndsAnOpenBlock() {
    let records = [
        edge(true, at: 1000),
        EventRecord(at: at(1400), event: .daemonStopped),
        EventRecord(at: at(1900), event: .daemonStarted(version: "0.1.0", dryRun: false)),
    ]
    let summary = AwayDigest.summarize(records: records, since: at(500), now: at(3000))
    #expect(summary == AwaySummary(blockCount: 1, awakeSeconds: 400, cutouts: []))
}

@Test func cutoutsInsideTheWindowAreListedOnce() {
    let records = [
        EventRecord(at: at(900), event: .cutoutLatched(.thermal)),
        EventRecord(at: at(1100), event: .cutoutLatched(.battery)),
        EventRecord(at: at(1200), event: .cutoutLatched(.battery)),
    ]
    let summary = AwayDigest.summarize(records: records, since: at(1000), now: at(2000))
    #expect(summary == AwaySummary(blockCount: 0, awakeSeconds: 0, cutouts: [.battery]))
    #expect(summary.lines == ["cutouts latched: battery"])
}

@Test func linesCombineAwakeTimeAndCutouts() {
    let summary = AwaySummary(blockCount: 3, awakeSeconds: 7260, cutouts: [.battery, .thermal])
    #expect(summary.lines == [
        "kept awake 2h1m across 3 blocks",
        "cutouts latched: battery, thermal",
    ])
}

@Test func decodeRecordsRoundTripsExactRecords() throws {
    let records = [
        edge(true, at: 1000),
        EventRecord(at: at(1100), event: .cutoutLatched(.battery)),
    ]
    var jsonl = Data()
    for record in records {
        try jsonl.append(EventLog.encode(record))
        jsonl.append(0x0A)
    }
    #expect(try AwayDigest.decodeRecords(fromJSONL: jsonl) == records)

    jsonl.append(Data("not json\n".utf8))
    #expect(throws: (any Error).self) {
        try AwayDigest.decodeRecords(fromJSONL: jsonl)
    }
}
