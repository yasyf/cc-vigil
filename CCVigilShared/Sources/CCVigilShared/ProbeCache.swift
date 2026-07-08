import Foundation

public struct ProbeCache: Equatable, Sendable {
    public struct Key: Hashable, Sendable {
        public let path: String
        public let mtime: Date
        public let size: Int64

        public init(path: String, mtime: Date, size: Int64) {
            self.path = path
            self.mtime = mtime
            self.size = size
        }
    }

    public enum Outcome: Equatable, Sendable {
        case probed(SessionProbe)
        case failed(message: String)
    }

    private struct Entry: Equatable {
        let key: Key
        let outcome: Outcome
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public var count: Int {
        entries.count
    }

    public func outcome(for key: Key) -> Outcome? {
        guard let entry = entries[key.path], entry.key == key else { return nil }
        return entry.outcome
    }

    public mutating func store(_ outcome: Outcome, for key: Key) {
        entries[key.path] = Entry(key: key, outcome: outcome)
    }

    public mutating func retain(paths: Set<String>) {
        entries = entries.filter { paths.contains($0.key) }
    }
}
