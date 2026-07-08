import CCVigilShared
import Foundation

public enum StateStore {
    public static func load(url: URL) throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try WireCodec.decodePayload(PersistedState.self, from: data)
    }

    public static func save(_ state: PersistedState, to url: URL) throws {
        try WireCodec.encodePayload(state).write(to: url, options: .atomic)
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
