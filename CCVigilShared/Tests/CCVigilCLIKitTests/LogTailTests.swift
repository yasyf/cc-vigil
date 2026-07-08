import CCVigilCLIKit
import Testing

@Test(arguments: [
    ("a\nb\nc\n", 2, ["b", "c"]),
    ("a\nb\nc", 2, ["b", "c"]),
    ("a\nb\nc\n", 10, ["a", "b", "c"]),
    ("", 5, []),
    ("only\n", 5, ["only"]),
    ("a\n\nb\n", 3, ["a", "", "b"]),
])
func tailsLastLines(text: String, count: Int, expected: [String]) {
    #expect(LogTail.lastLines(of: text, count: count) == expected)
}
