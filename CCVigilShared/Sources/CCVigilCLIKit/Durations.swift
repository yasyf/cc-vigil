public enum DurationParseError: Error, Equatable, CustomStringConvertible {
    case invalid(String)
    case nonPositive(String)

    public var description: String {
        switch self {
        case let .invalid(text):
            "invalid duration '\(text)': use seconds or <n>s|m|h|d, e.g. 90, 45m, 2h, 1h30m"
        case let .nonPositive(text):
            "duration must be positive: '\(text)'"
        }
    }
}

public enum Durations {
    static let secondsPerUnit: [Character: Int] = ["s": 1, "m": 60, "h": 3600, "d": 86400]

    public static func seconds(from text: String) throws -> Int {
        guard !text.isEmpty else { throw DurationParseError.invalid(text) }
        var total = 0
        var digits = ""
        var sawUnit = false
        for character in text {
            if character.isASCII, character.isWholeNumber {
                digits.append(character)
            } else if let multiplier = secondsPerUnit[character] {
                guard let value = Int(digits) else { throw DurationParseError.invalid(text) }
                let (scaled, multiplyOverflowed) = value.multipliedReportingOverflow(by: multiplier)
                guard !multiplyOverflowed else { throw DurationParseError.invalid(text) }
                let (sum, addOverflowed) = total.addingReportingOverflow(scaled)
                guard !addOverflowed else { throw DurationParseError.invalid(text) }
                total = sum
                digits = ""
                sawUnit = true
            } else {
                throw DurationParseError.invalid(text)
            }
        }
        if !digits.isEmpty {
            guard !sawUnit, let value = Int(digits) else { throw DurationParseError.invalid(text) }
            total = value
        }
        guard total > 0 else { throw DurationParseError.nonPositive(text) }
        return total
    }

    public static func text(forSeconds seconds: Int) -> String {
        guard seconds > 0 else { return "0s" }
        var remaining = seconds
        var parts: [String] = []
        for (unit, size) in [("d", 86400), ("h", 3600), ("m", 60), ("s", 1)] where remaining >= size {
            parts.append("\(remaining / size)\(unit)")
            remaining %= size
        }
        return parts.joined()
    }
}
