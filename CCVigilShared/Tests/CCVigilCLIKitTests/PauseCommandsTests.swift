import CCVigilCLIKit
import CCVigilShared
import Testing

@Test(arguments: [
    ("30m", 1800),
    ("2h", 7200),
    ("1d", 86400),
    ("100d", 86400),
    ("1000000", 86400),
])
func clampsPauseDurationToTheDayCeiling(duration: String, expected: Int) throws {
    #expect(try PauseCommand.clampedSeconds(from: duration) == expected)
    #expect(expected <= Hold.maxTTLSeconds)
}
