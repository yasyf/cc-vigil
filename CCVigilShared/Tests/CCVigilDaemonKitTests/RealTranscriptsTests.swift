import CCVigilDaemonKit
import CCVigilShared
import Foundation
import Testing

// Integration-ish: reads THIS machine's real ~/.claude/projects (read-only)
// and asserts the oracle survives arbitrary real transcripts with plausible
// output. Passes trivially on machines without Claude Code.
@Test func realTranscriptsProbeWithoutCrashing() {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)
    let oracle = TranscriptOracle(roots: [root])
    let clock = SystemClock()
    let collection = oracle.collect(config: .default, clock: clock)

    let nowEpoch = Int64(clock.now.timeIntervalSince1970)
    let earliestPlausible: Int64 = 1_577_836_800 // 2020-01-01
    for probe in collection.probes {
        #expect(probe.sessionPath.hasSuffix(".jsonl"))
        if let epoch = probe.lastEventEpoch {
            #expect(epoch > earliestPlausible)
            #expect(epoch <= nowEpoch + 86400)
        }
    }
    for failure in collection.newFailures {
        #expect(failure.path.hasSuffix(".jsonl"))
        #expect(!failure.message.isEmpty)
    }

    let decision = OracleState(
        sessions: collection.probes,
        humanWaitHints: [:],
        backgroundWork: [:],
        claudeProcessesAlive: true
    ).decision(config: .default, clock: clock)
    #expect(decision.activeSessions.count + decision.discounts.count <= collection.probes.count * 2)
}
