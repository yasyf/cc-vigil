import CCVigilShared
import Foundation
import Testing

private func procArgs2(argc: UInt32, execPath: String, strings: [String]) -> Data {
    var data = Data()
    withUnsafeBytes(of: argc.littleEndian) { data.append(contentsOf: $0) }
    data.append(contentsOf: Array(execPath.utf8))
    data.append(contentsOf: [0, 0, 0])
    for string in strings {
        data.append(contentsOf: Array(string.utf8))
        data.append(0)
    }
    return data
}

@Test func parsesArgvSkippingExecPathAndPadding() {
    let data = procArgs2(
        argc: 3,
        execPath: "/Users/u/.local/bin/claude",
        strings: ["claude", "--resume", "abc", "HOME=/Users/u", "PATH=/bin"]
    )
    #expect(ProcArgsParser.argv(fromProcArgs2: data) == ["claude", "--resume", "abc"])
}

@Test func parsesSingleArgumentProcess() {
    let data = procArgs2(argc: 1, execPath: "/bin/ls", strings: ["ls", "TERM=xterm"])
    #expect(ProcArgsParser.argv(fromProcArgs2: data) == ["ls"])
}

@Test(arguments: [
    ("empty", Data()),
    ("header only", Data([2, 0, 0, 0])),
    ("zero argc", procArgs2(argc: 0, execPath: "/bin/ls", strings: ["ls"])),
    ("absurd argc", procArgs2(argc: 100_000, execPath: "/bin/ls", strings: ["ls"])),
    ("truncated argv", procArgs2(argc: 4, execPath: "/bin/ls", strings: ["ls", "-la"])),
])
func rejectsMalformedBuffers(label: String, data: Data) {
    #expect(ProcArgsParser.argv(fromProcArgs2: data) == nil, "\(label) must parse to nil")
}

@Test(arguments: [
    (["/Users/u/.local/bin/claude", "--resume"], true),
    (["claude"], true),
    (["/usr/local/bin/node", "/Users/u/.nvm/bin/claude", "--print"], true),
    (["/bin/bash", "/Users/u/.superset/bin/claude"], true),
    (["/usr/bin/vim", "claude"], false),
    (["/Applications/Claude.app/Contents/MacOS/Claude"], false),
    (["/usr/local/bin/claude-code-router"], false),
    (["/bin/ls"], false),
    ([], false),
])
func matchesClaudeCommandLines(argv: [String], expected: Bool) {
    #expect(ClaudeProcessMatcher.isClaude(argv: argv) == expected)
}
