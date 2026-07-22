import CCVigilRuntime
import CCVigilShared
import Foundation
import Testing

@Test func scansNestedProjectsAndSkipsNonTranscripts() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let alpha = try transcripts.install(fixture: "active-recent", as: "aaa.jsonl", in: "p1")
    let beta = try transcripts.install(fixture: "mid-tool", as: "bbb.jsonl", in: "p2/nested")
    try Data("notes".utf8).write(to: transcripts.root.appendingPathComponent("p1/readme.md"))

    let entries = TranscriptScanner(roots: [transcripts.root]).entries().sorted { $0.path < $1.path }
    #expect(entries.map(\.path) == [alpha.path, beta.path].sorted())
    let alphaEntry = try #require(entries.first { $0.path == alpha.path })
    #expect(alphaEntry.size == 323)
    #expect(alphaEntry.mtime == Date(timeIntervalSince1970: TimeInterval(fixtureLastEventEpoch)))
    #expect(alphaEntry.fileID != 0)
}

@Test func resolvesSymlinksAndDedupesByRealPath() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let real = try transcripts.install(fixture: "active-recent", as: "real.jsonl", in: "p1")
    let linkDirectory = transcripts.root.appendingPathComponent("p2", isDirectory: true)
    try FileManager.default.createDirectory(at: linkDirectory, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: linkDirectory.appendingPathComponent("link.jsonl"),
        withDestinationURL: real
    )

    let entries = TranscriptScanner(roots: [transcripts.root]).entries()
    #expect(entries.map(\.path) == [real.resolvingSymlinksInPath().path])
}

@Test func excludesSubagentSidechainTranscripts() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let session = try transcripts.install(fixture: "active-recent", as: "session.jsonl", in: "p1")
    try transcripts.install(fixture: "active-recent", as: "agent-x.jsonl", in: "p1/session/subagents")

    let entries = TranscriptScanner(roots: [transcripts.root]).entries()
    #expect(entries.map(\.path) == [session.resolvingSymlinksInPath().path])
}

@Test func scansWhenRootPathContainsSubagentsAncestor() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let session = try transcripts.install(fixture: "active-recent", as: "session.jsonl", in: "subagents/projects/p1")
    let root = transcripts.root.appendingPathComponent("subagents/projects", isDirectory: true)

    let entries = TranscriptScanner(roots: [root]).entries()
    #expect(entries.map(\.path) == [session.resolvingSymlinksInPath().path])
}

@Test func excludesSymlinkResolvingIntoSubagents() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let session = try transcripts.install(fixture: "active-recent", as: "session.jsonl", in: "p1")
    let sidechain = try transcripts.install(fixture: "active-recent", as: "agent-x.jsonl", in: "p1/session/subagents")
    let linkDirectory = transcripts.root.appendingPathComponent("p2", isDirectory: true)
    try FileManager.default.createDirectory(at: linkDirectory, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: linkDirectory.appendingPathComponent("link.jsonl"),
        withDestinationURL: sidechain
    )

    let entries = TranscriptScanner(roots: [transcripts.root]).entries()
    #expect(entries.map(\.path) == [session.resolvingSymlinksInPath().path])
}

@Test func missingRootScansToEmpty() {
    let scanner = TranscriptScanner(roots: [URL(fileURLWithPath: "/nonexistent/never/projects")])
    #expect(scanner.entries() == [])
}

@Test func scansMultipleRootsAndDedupesASymlinkedOverlap() throws {
    let transcripts = try TranscriptsRoot()
    defer { transcripts.tearDown() }
    let primary = try transcripts.install(fixture: "active-recent", as: "session.jsonl", in: "p1")
    let relocated = try TranscriptsRoot()
    defer { relocated.tearDown() }
    let relocatedSession = try relocated.install(fixture: "mid-tool", as: "other.jsonl", in: "q1")
    // A second root that is a symlink into the primary root: its transcript
    // resolves to the primary's real path and must be counted once.
    let overlap = relocated.root.appendingPathComponent("overlap", isDirectory: true)
    try FileManager.default.createSymbolicLink(
        at: overlap,
        withDestinationURL: transcripts.root.appendingPathComponent("p1", isDirectory: true)
    )

    let entries = TranscriptScanner(roots: [transcripts.root, relocated.root])
        .entries()
        .map(\.path)
        .sorted()
    #expect(entries == [primary.resolvingSymlinksInPath().path, relocatedSession.resolvingSymlinksInPath().path].sorted())
}
