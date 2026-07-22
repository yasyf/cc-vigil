import CCVigilShared
import Foundation

public struct ProbeFailure: Equatable, Sendable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct OracleCollection: Equatable, Sendable {
    public let probes: [SessionProbe]
    public let newFailures: [ProbeFailure]

    public init(probes: [SessionProbe], newFailures: [ProbeFailure]) {
        self.probes = probes
        self.newFailures = newFailures
    }
}

public final class TranscriptOracle {
    private var scanner: TranscriptScanner
    private let prober = TranscriptProber()
    private var cache = ProbeCache()

    public init(roots: [URL]) {
        scanner = TranscriptScanner(roots: roots)
    }

    /// Scans an additional root without discarding the probe cache. Callers
    /// dedupe by real path before adding; a redundant root only wastes an
    /// enumeration, since the scanner keys entries by real path.
    public func addRoot(_ root: URL) {
        scanner = TranscriptScanner(roots: scanner.roots + [root])
    }

    public func collect(
        config: VigilConfig,
        clock: some WallClock,
        pinnedSessionIDs: Set<String>
    ) -> OracleCollection {
        let selected = TranscriptDiscoveryPolicy.select(
            entries: scanner.entries(),
            config: config,
            now: clock.now,
            pinnedSessionIDs: pinnedSessionIDs
        )
        cache.retain(paths: Set(selected.map(\.path)))
        var probes: [SessionProbe] = []
        var newFailures: [ProbeFailure] = []
        for entry in selected {
            let key = ProbeCache.Key(
                path: entry.path,
                mtime: entry.mtime,
                size: entry.size,
                fileID: entry.fileID
            )
            let outcome: ProbeCache.Outcome
            if let cached = cache.outcome(for: key) {
                outcome = cached
            } else {
                outcome = freshOutcome(path: entry.path)
                cache.store(outcome, for: key)
                if case let .failed(message) = outcome {
                    newFailures.append(ProbeFailure(path: entry.path, message: message))
                }
            }
            switch outcome {
            case let .probed(probe):
                probes.append(probe)
            case .failed:
                if let lastGood = cache.lastKnownGood(forPath: entry.path) {
                    probes.append(Self.reassertedProbe(from: lastGood, entry: entry))
                } else {
                    probes.append(Self.recencyProbe(for: entry))
                }
            }
        }
        return OracleCollection(probes: probes, newFailures: newFailures)
    }

    private static func reassertedProbe(from lastGood: SessionProbe, entry: TranscriptFileEntry) -> SessionProbe {
        let mtimeEpoch = Int64(entry.mtime.timeIntervalSince1970)
        return SessionProbe(
            sessionPath: entry.path,
            isWaiting: lastGood.isWaiting,
            midTool: lastGood.midTool,
            lastEventEpoch: lastGood.lastEventEpoch.map { max($0, mtimeEpoch) } ?? mtimeEpoch,
            pending: lastGood.pending
        )
    }

    private static func recencyProbe(for entry: TranscriptFileEntry) -> SessionProbe {
        SessionProbe(
            sessionPath: entry.path,
            isWaiting: false,
            midTool: false,
            lastEventEpoch: Int64(entry.mtime.timeIntervalSince1970),
            pending: []
        )
    }

    private func freshOutcome(path: String) -> ProbeCache.Outcome {
        do {
            return try .probed(prober.probe(path: path))
        } catch let error as TranscriptProbeError {
            return .failed(message: error.message)
        } catch {
            return .failed(message: String(describing: error))
        }
    }
}
