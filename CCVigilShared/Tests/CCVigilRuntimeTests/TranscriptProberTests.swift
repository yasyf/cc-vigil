import CCVigilRuntime
import CCVigilShared
import Foundation
import Testing

@Test func probesCompletedExchangeAsQuiet() throws {
    let path = try fixtureURL("active-recent").path
    let probe = try TranscriptProber().probe(path: path)
    #expect(probe == SessionProbe(
        sessionPath: path,
        isWaiting: false,
        midTool: false,
        lastEventEpoch: fixtureLastEventEpoch,
        pending: []
    ))
}

@Test func probesUnmatchedToolUseAsMidTool() throws {
    let probe = try TranscriptProber().probe(path: fixtureURL("mid-tool").path)
    #expect(probe.midTool == true)
    #expect(probe.isWaiting == false)
    #expect(probe.lastEventEpoch == fixtureLastEventEpoch)
    #expect(probe.pending == [PendingItem(toolUseID: "b1", name: "Bash", kind: .midTool)])
}

@Test func probesPendingWorkflowAsWaiting() throws {
    let probe = try TranscriptProber().probe(path: fixtureURL("waiting-workflow").path)
    #expect(probe.isWaiting == true)
    #expect(probe.midTool == false)
    #expect(probe.lastEventEpoch == fixtureLastEventEpoch)
    #expect(probe.pending == [PendingItem(toolUseID: "wf1", name: "Workflow", kind: .pendingAsyncWorkflow)])
}

@Test func malformedTranscriptThrowsInsteadOfCrashing() throws {
    #expect(throws: TranscriptProbeError.self) {
        try TranscriptProber().probe(path: fixtureURL("malformed").path)
    }
}

@Test func missingTranscriptThrows() {
    #expect(throws: TranscriptProbeError.self) {
        try TranscriptProber().probe(path: "/nonexistent/never/here.jsonl")
    }
}
