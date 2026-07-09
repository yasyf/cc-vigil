import Foundation

public enum NudgeStdinError: Error, Equatable, CustomStringConvertible {
    case oversized(limit: Int)

    public var description: String {
        switch self {
        case let .oversized(limit):
            "stdin exceeds the \(limit)-byte nudge cap; ignoring the hook event"
        }
    }
}

public enum NudgeStdin {
    public static let maxBytes = 4 * 1024 * 1024

    public static func read(from handle: FileHandle, limit: Int = maxBytes) throws -> Data {
        var data = Data()
        while true {
            let remaining = limit + 1 - data.count
            guard remaining > 0 else { throw NudgeStdinError.oversized(limit: limit) }
            guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                return data
            }
            data.append(chunk)
        }
    }
}
