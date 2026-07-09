import CCVigilShared
import Foundation
import os

private extension Logger {
    static let stateStore = Logger(subsystem: "dev.yasyf.cc-vigil", category: "StateStore")
    static let configLoader = Logger(subsystem: "dev.yasyf.cc-vigil", category: "ConfigLoader")
}

/// A resiliency daemon must not brick on a corrupt on-disk file: KeepAlive + exit(78) on
/// decode failure is a crash-loop with zero sleep protection. Move the corrupt bytes aside
/// (overwriting any prior quarantine) so the caller can start fresh. Best-effort by
/// contract — a quarantine that itself fails is logged loudly and swallowed, because the
/// caller must recover regardless. The only loss is TTL-bounded holds/pause (state) or an
/// override config (defaults) — an acceptable trade for staying alive.
private func quarantineCorruptFile(at url: URL, cause: Error, log: Logger) {
    let corrupt = url.appendingPathExtension("corrupt")
    let detail = String(describing: cause)
    do {
        try FileManager.default.removeItem(at: corrupt)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
        // No prior quarantine to clear.
    } catch {
        log.fault(
            "stale quarantine \(corrupt.path, privacy: .public) could not be cleared: \(String(describing: error), privacy: .public)"
        )
    }
    do {
        try FileManager.default.moveItem(at: url, to: corrupt)
    } catch {
        log.fault(
            """
            corrupt file \(url.path, privacy: .public) could not be quarantined; starting fresh anyway. \
            decode failure: \(detail, privacy: .public); quarantine failure: \(String(describing: error), privacy: .public)
            """
        )
        return
    }
    log.fault(
        "corrupt file \(url.path, privacy: .public) quarantined to \(corrupt.path, privacy: .public); starting fresh: \(detail, privacy: .public)"
    )
}

public enum StateStore {
    public static func load(url: URL) throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try WireCodec.decodePayload(PersistedState.self, from: data)
        } catch {
            quarantineCorruptFile(at: url, cause: error, log: .stateStore)
            return PersistedState(holds: [], pausedUntil: nil)
        }
    }

    public static func save(_ state: PersistedState, to url: URL) throws {
        try WireCodec.encodePayload(state).write(to: url, options: .atomic)
    }
}

public enum ConfigLoader {
    public static func load(url: URL) throws -> VigilConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }
        let data = try Data(contentsOf: url)
        do {
            return try WireCodec.decodePayload(VigilConfig.self, from: data)
        } catch {
            quarantineCorruptFile(at: url, cause: error, log: .configLoader)
            return .default
        }
    }

    public static func save(_ config: VigilConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
