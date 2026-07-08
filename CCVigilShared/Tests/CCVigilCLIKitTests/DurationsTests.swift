import CCVigilCLIKit
import Testing

@Test(arguments: [
    ("90", 90),
    ("30s", 30),
    ("5m", 300),
    ("2h", 7200),
    ("1d", 86400),
    ("1h30m", 5400),
    ("2m30s", 150),
    ("1d2h", 93600),
])
func parsesValidDurations(text: String, expected: Int) throws {
    #expect(try Durations.seconds(from: text) == expected)
}

@Test(arguments: ["", "abc", "5x", "m", "1h30", "-5m", " 5m", "9999999999999999999999d"])
func rejectsInvalidDurations(text: String) {
    #expect(throws: DurationParseError.invalid(text)) {
        try Durations.seconds(from: text)
    }
}

@Test(arguments: ["0", "0s", "0h0m"])
func rejectsNonPositiveDurations(text: String) {
    #expect(throws: DurationParseError.nonPositive(text)) {
        try Durations.seconds(from: text)
    }
}

@Test(arguments: [
    (0, "0s"),
    (45, "45s"),
    (90, "1m30s"),
    (3600, "1h"),
    (5400, "1h30m"),
    (86400, "1d"),
    (90061, "1d1h1m1s"),
])
func formatsDurations(seconds: Int, expected: String) {
    #expect(Durations.text(forSeconds: seconds) == expected)
}
