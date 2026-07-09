import CCVigilShared
import Foundation
import os

private extension Logger {
    static let stateStore = Logger(subsystem: "dev.yasyf.cc-vigil", category: "StateStore")
}

public enum StateStore {
    public static func load(url: URL) throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try WireCodec.decodePayload(PersistedState.self, from: data)
        } catch {
            return try quarantine(url, cause: error)
        }
    }

    public static func save(_ state: PersistedState, to url: URL) throws {
        try WireCodec.encodePayload(state).write(to: url, options: .atomic)
    }

    /// A resiliency daemon must not brick on its own state file: KeepAlive + exit(78)
    /// on decode failure is a crash-loop with zero sleep protection. Quarantine the
    /// corrupt bytes (overwriting any prior quarantine) and start fresh. The only loss
    /// is TTL-bounded holds/pause — an acceptable trade for staying alive.
    private static func quarantine(_ url: URL, cause: Error) throws -> PersistedState {
        let corrupt = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: corrupt)
        try FileManager.default.moveItem(at: url, to: corrupt)
        let detail = String(describing: cause)
        Logger.stateStore.fault(
            "corrupt state \(url.path, privacy: .public) quarantined; starting fresh: \(detail, privacy: .public)"
        )
        return PersistedState(holds: [], pausedUntil: nil)
    }
}

public enum ConfigLoader {
    public static func load(url: URL) throws -> VigilConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }
        let data = try Data(contentsOf: url)
        return try WireCodec.decodePayload(VigilConfig.self, from: data)
    }

    public static func save(_ config: VigilConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
