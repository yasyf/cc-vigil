import CCVigilShared
import Foundation
import Testing

private func probe(path: String = "/t/a.jsonl", epoch: Int64 = 100) -> SessionProbe {
    SessionProbe(sessionPath: path, isWaiting: false, midTool: true, lastEventEpoch: epoch, pending: [])
}

private func key(path: String = "/t/a.jsonl", mtime: Int64 = 1000, size: Int64 = 64) -> ProbeCache.Key {
    ProbeCache.Key(path: path, mtime: Date(timeIntervalSince1970: TimeInterval(mtime)), size: size)
}

@Test func missesOnEmptyCache() {
    let cache = ProbeCache()
    #expect(cache.outcome(for: key()) == nil)
}

@Test func hitsOnIdenticalKey() {
    var cache = ProbeCache()
    cache.store(.probed(probe()), for: key())
    #expect(cache.outcome(for: key()) == .probed(probe()))
}

@Test(arguments: [
    ("mtime", key(mtime: 1001, size: 64)),
    ("size", key(mtime: 1000, size: 65)),
])
func missesWhenKeyComponentChanges(component: String, changed: ProbeCache.Key) {
    var cache = ProbeCache()
    cache.store(.probed(probe()), for: key())
    #expect(cache.outcome(for: changed) == nil, "\(component) change must invalidate")
}

@Test func cachesFailuresUnderSameKeying() {
    var cache = ProbeCache()
    cache.store(.failed(message: "bad json"), for: key())
    #expect(cache.outcome(for: key()) == .failed(message: "bad json"))
    #expect(cache.outcome(for: key(mtime: 2000)) == nil)
}

@Test func storeReplacesEntryForSamePath() {
    var cache = ProbeCache()
    cache.store(.probed(probe(epoch: 100)), for: key(mtime: 1000))
    cache.store(.probed(probe(epoch: 200)), for: key(mtime: 2000))
    #expect(cache.count == 1)
    #expect(cache.outcome(for: key(mtime: 1000)) == nil)
    #expect(cache.outcome(for: key(mtime: 2000)) == .probed(probe(epoch: 200)))
}

@Test func retainDropsUndiscoveredPaths() {
    var cache = ProbeCache()
    cache.store(.probed(probe(path: "/t/a.jsonl")), for: key(path: "/t/a.jsonl"))
    cache.store(.probed(probe(path: "/t/b.jsonl")), for: key(path: "/t/b.jsonl"))
    cache.retain(paths: ["/t/b.jsonl"])
    #expect(cache.count == 1)
    #expect(cache.outcome(for: key(path: "/t/a.jsonl")) == nil)
    #expect(cache.outcome(for: key(path: "/t/b.jsonl")) == .probed(probe(path: "/t/b.jsonl")))
}
