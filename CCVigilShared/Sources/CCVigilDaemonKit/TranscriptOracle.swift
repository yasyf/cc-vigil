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
    private let scanner: TranscriptScanner
    private let prober = TranscriptProber()
    private var cache = ProbeCache()

    public init(root: URL) {
        scanner = TranscriptScanner(root: root)
    }

    public func collect(config: VigilConfig, clock: some WallClock) -> OracleCollection {
        let selected = TranscriptDiscoveryPolicy.select(
            entries: scanner.entries(),
            config: config,
            now: clock.now
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
                probes.append(Self.recencyProbe(for: entry))
            }
        }
        return OracleCollection(probes: probes, newFailures: newFailures)
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
