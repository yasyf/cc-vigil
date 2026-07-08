import CCVigilDaemonKit
import CCVigilShared

protocol ClaudeProcessListing: Sendable {
    func claudeProcessesAlive() -> Bool
}

struct SysctlClaudeProcessLister: ClaudeProcessListing {
    func claudeProcessesAlive() -> Bool {
        ProcessFacts.userPids().contains { pid in
            guard let argv = ProcessFacts.argv(pid: pid) else { return false }
            return ClaudeProcessMatcher.isClaude(argv: argv)
        }
    }
}
