import CCVigilRuntime
import CCVigilShared
import Darwin

public enum ClaudeAncestry {
    public static let maxDepth = 64

    public static func nearestClaudePid(
        startingAt pid: Int32,
        parent: (Int32) -> Int32?,
        argv: (Int32) -> [String]?
    ) -> Int32? {
        var current = pid
        for _ in 0 ..< maxDepth {
            guard current > 1 else { return nil }
            if let argv = argv(current), ClaudeProcessMatcher.isClaude(argv: argv) {
                return current
            }
            guard let next = parent(current), next != current else { return nil }
            current = next
        }
        return nil
    }

    public static func nearestClaudeAncestorOfSelf() -> Int32? {
        nearestClaudePid(
            startingAt: getppid(),
            parent: ProcessFacts.parentPid(of:),
            argv: ProcessFacts.argv(pid:)
        )
    }
}
