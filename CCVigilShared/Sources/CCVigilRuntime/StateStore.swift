import CCVigilShared
import Foundation

public enum StateStore {
    public static func load(url: URL) throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try PersistedSchemaCodec.decodeState(data)
    }

    public static func save(_ state: PersistedState, to url: URL) throws {
        try PersistedSchemaCodec.encodeState(state).write(to: url, options: .atomic)
    }
}

public enum ConfigLoader {
    public static func load(url: URL) throws -> VigilConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }
        let data = try Data(contentsOf: url)
        return try PersistedSchemaCodec.decodeConfig(data)
    }

    public static func save(_ config: VigilConfig, to url: URL) throws {
        try PersistedSchemaCodec.encodeConfig(config).write(to: url, options: .atomic)
    }
}
