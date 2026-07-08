import CCVigilShared
import Foundation
import os

public final class EventLog: Sendable {
    public static let maxBytes = 10 * 1024 * 1024

    private let url: URL
    private let rotatedURL: URL
    private let maxBytes: Int
    private let lock = OSAllocatedUnfairLock()

    public init(url: URL, maxBytes: Int = EventLog.maxBytes) {
        self.url = url
        rotatedURL = url.appendingPathExtension("1")
        self.maxBytes = maxBytes
    }

    public func append(_ record: EventRecord) throws {
        let line = try WireCodec.encodePayload(record) + Data([0x0A])
        try lock.withLock {
            try lockedAppend(line)
        }
    }

    private func lockedAppend(_ line: Data) throws {
        let fileManager = FileManager.default
        let currentSize = (try? fileManager.attributesOfItem(atPath: url.path))
            .flatMap { ($0[.size] as? NSNumber)?.intValue } ?? 0
        if currentSize > 0, currentSize + line.count > maxBytes {
            if fileManager.fileExists(atPath: rotatedURL.path) {
                try fileManager.removeItem(at: rotatedURL)
            }
            try fileManager.moveItem(at: url, to: rotatedURL)
        }
        if !fileManager.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
