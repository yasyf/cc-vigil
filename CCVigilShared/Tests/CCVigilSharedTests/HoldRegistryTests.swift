import CCVigilShared
import Foundation
import Testing

private let epoch: Int64 = 1_800_000_000
private let clock = FixedClock(epoch: epoch)

private func hold(
    key: String = "k",
    ttlSeconds: Int = 3600,
    createdAt: Int64 = epoch,
    pid: Int32? = nil
) -> Hold {
    Hold(
        key: key,
        reason: "r",
        ttlSeconds: ttlSeconds,
        createdAt: Date(timeIntervalSince1970: TimeInterval(createdAt)),
        pid: pid
    )
}

@Test(arguments: [
    (90000, 86400),
    (86400, 86400),
    (3600, 3600),
])
func holdClampsTTLTo24Hours(requested: Int, expected: Int) {
    var registry = HoldRegistry()
    let hold = registry.add(key: "k", reason: "r", ttlSeconds: requested, pid: nil, clock: clock)
    #expect(hold.ttlSeconds == expected)
}

@Test func holdTTLClampSurvivesDecoding() throws {
    let json = Data(
        #"{"key":"k","reason":"r","ttlSeconds":90000,"createdAt":1800000000,"pid":null}"#.utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try decoder.decode(Hold.self, from: json)
    #expect(decoded.ttlSeconds == 86400)
}

@Test func holdAddRecordsCreationFacts() {
    var registry = HoldRegistry()
    let hold = registry.add(key: "deploy", reason: "long deploy", ttlSeconds: 600, pid: 42, clock: clock)
    #expect(hold == Hold(
        key: "deploy",
        reason: "long deploy",
        ttlSeconds: 600,
        createdAt: clock.now,
        pid: 42
    ))
    #expect(registry.holds == [hold])
}

@Test func holdDuplicateKeyLastWins() {
    var registry = HoldRegistry()
    registry.add(key: "k", reason: "first", ttlSeconds: 600, pid: nil, clock: clock)
    registry.add(key: "other", reason: "other", ttlSeconds: 600, pid: nil, clock: clock)
    let replacement = registry.add(key: "k", reason: "second", ttlSeconds: 1200, pid: 7, clock: clock)
    #expect(registry.holds.count == 2)
    #expect(registry.holds.last == replacement)
    #expect(registry.holds.first?.key == "other")
}

@Test func holdReleaseRemovesAndReturns() {
    var registry = HoldRegistry()
    let added = registry.add(key: "k", reason: "r", ttlSeconds: 600, pid: nil, clock: clock)
    #expect(registry.release(key: "k") == added)
    #expect(registry.holds.isEmpty)
    #expect(registry.release(key: "k") == nil)
}

@Test(arguments: [
    (Int64(59), true),
    (Int64(60), false),
])
func holdExpiryBoundary(elapsed: Int64, expectActive: Bool) {
    let registry = HoldRegistry(holds: [hold(ttlSeconds: 60)])
    let later = FixedClock(epoch: epoch + elapsed)
    #expect(registry.active(clock: later).count == (expectActive ? 1 : 0))
}

@Test func holdPruneRemovesOnlyExpired() {
    var registry = HoldRegistry(holds: [
        hold(key: "expired", ttlSeconds: 60),
        hold(key: "live", ttlSeconds: 600),
    ])
    let later = FixedClock(epoch: epoch + 100)
    let removed = registry.prune(clock: later)
    #expect(removed.map(\.key) == ["expired"])
    #expect(registry.holds.map(\.key) == ["live"])
}

@Test(arguments: [
    ("pre-boot", Int64(-10), Int32?.none, Int64?.none, false),
    ("at-boot", Int64(0), Int32?.none, Int64?.none, true),
    ("no-pid", Int64(10), Int32?.none, Int64?.none, true),
    ("dead-pid", Int64(10), Int32?(99), Int64?.none, false),
    ("recycled-pid", Int64(10), Int32?(99), Int64?(epoch + 20), false),
    ("live-pid-started-at-creation", Int64(10), Int32?(99), Int64?(epoch + 10), true),
    ("live-pid-started-earlier", Int64(10), Int32?(99), Int64?(epoch), true),
])
func holdRestoreFilter(
    label: String,
    createdOffset: Int64,
    pid: Int32?,
    processStartEpoch: Int64?,
    expectKept: Bool
) {
    let candidate = hold(key: label, createdAt: epoch + createdOffset, pid: pid)
    let registry = HoldRegistry.restored(
        from: [candidate],
        bootedAt: Date(timeIntervalSince1970: TimeInterval(epoch)),
        processStart: { queried in
            #expect(queried == pid)
            return processStartEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
    )
    #expect(registry.holds == (expectKept ? [candidate] : []))
}
