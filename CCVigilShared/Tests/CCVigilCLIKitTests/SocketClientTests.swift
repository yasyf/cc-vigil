import CCVigilCLIKit
import CCVigilShared
import Foundation
import Testing

private let sampleReport = StatusReport(
    shouldBlock: true,
    blockApplied: true,
    helper: .reachable,
    activeSessions: [ActiveSession(path: "/t/s.jsonl", reasons: [.waiting])],
    holds: [Hold(
        key: "k",
        reason: "r",
        ttlSeconds: 600,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        pid: nil
    )],
    latchedCutouts: [],
    pausedUntil: nil
)

@Test func roundTripsPing() throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .respond(.ok))
    try server.start()
    defer { server.stop() }
    let client = SocketClient(path: server.path, timeoutSeconds: 2)
    #expect(try client.roundTrip(.ping) == .ok)
    #expect(server.requests == [.ping])
}

@Test func roundTripsStatusReport() throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .respond(.status(sampleReport)))
    try server.start()
    defer { server.stop() }
    let client = SocketClient(path: server.path, timeoutSeconds: 2)
    #expect(try client.roundTrip(.status) == .status(sampleReport))
    #expect(server.requests == [.status])
}

@Test func deliversDaemonErrors() throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    let server = FakeSocketServer(
        path: dir.socketPath("s.sock"),
        reply: .respond(.error(message: "no hold with key k"))
    )
    try server.start()
    defer { server.stop() }
    let client = SocketClient(path: server.path, timeoutSeconds: 2)
    #expect(try client.roundTrip(.release(key: "k")) == .error(message: "no hold with key k"))
    #expect(server.requests == [.release(key: "k")])
}

@Test func failsToConnectWithoutServer() throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    let client = SocketClient(path: dir.socketPath("missing.sock"), timeoutSeconds: 1)
    #expect(throws: SocketClientError.connectFailed(errno: ENOENT)) {
        try client.roundTrip(.ping)
    }
}

@Test func timesOutOnSilentServer() throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .silence)
    try server.start()
    defer { server.stop() }
    let client = SocketClient(path: server.path, timeoutSeconds: 1)
    #expect(throws: SocketClientError.replyTimedOut(afterSeconds: 1)) {
        try client.roundTrip(.status)
    }
}

@Test func sendDeliversWithoutAwaitingAReply() throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    // The server always replies, mirroring production: send() closes without
    // reading it, and neither peer may take SIGPIPE writing to the gone side.
    let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .respond(.ok))
    try server.start()
    defer { server.stop() }
    let client = SocketClient(path: server.path, timeoutSeconds: 5)
    let payload = NudgePayload(sessionId: "s", hookEvent: "PreToolUse")
    try client.send(.nudge(payload))
    let deadline = Date().addingTimeInterval(2)
    while server.requests.isEmpty, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.005)
    }
    #expect(server.requests == [.nudge(payload)])
}

@Test func reportsClosedConnection() throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .raw(Data()))
    try server.start()
    defer { server.stop() }
    let client = SocketClient(path: server.path, timeoutSeconds: 1)
    #expect(throws: SocketClientError.connectionClosed) {
        try client.roundTrip(.status)
    }
}

@Test func reportsMalformedReplies() throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    let junk = try WireFrame.encode(payload: Data(#"{"result":"bogus"}"#.utf8))
    let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .raw(junk))
    try server.start()
    defer { server.stop() }
    let client = SocketClient(path: server.path, timeoutSeconds: 1)
    do {
        _ = try client.roundTrip(.status)
        Issue.record("expected a malformedReply error")
    } catch let error as SocketClientError {
        guard case .malformedReply = error else {
            Issue.record("expected malformedReply, got \(error)")
            return
        }
    }
}

@Test func rejectsOverlongSocketPaths() {
    let path = "/tmp/" + String(repeating: "x", count: 120) + ".sock"
    let client = SocketClient(path: path, timeoutSeconds: 1)
    #expect(throws: SocketClientError.pathTooLong(path)) {
        try client.roundTrip(.ping)
    }
}
