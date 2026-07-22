import CCVigilCLIKit
import CCVigilShared
import CCVigilTransport
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

@Suite(.serialized)
struct CLIDaemonClientTests {
    @Test func roundTripsPing() throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .respond(.ok))
        try server.start()
        defer { server.stop() }
        let client = CLIDaemonClient(path: server.path, timeoutSeconds: 2)
        #expect(try client.roundTrip(.ping) == .ok)
        #expect(try client.roundTrip(.ping) == .ok)
        #expect(server.requests == [.ping, .ping])
    }

    @Test func roundTripsStatusReport() throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .respond(.status(sampleReport)))
        try server.start()
        defer { server.stop() }
        let client = CLIDaemonClient(path: server.path, timeoutSeconds: 2)
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
        let client = CLIDaemonClient(path: server.path, timeoutSeconds: 2)
        #expect(try client.roundTrip(.release(key: "k")) == .error(message: "no hold with key k"))
        #expect(server.requests == [.release(key: "k")])
    }

    @Test func failsToConnectWithoutServer() throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let client = CLIDaemonClient(path: dir.socketPath("missing.sock"), timeoutSeconds: 1)
        do {
            _ = try client.roundTrip(.ping)
            Issue.record("expected a transport error")
        } catch let error as DaemonClientError {
            guard case .transport = error else {
                Issue.record("expected transport, got \(error)")
                return
            }
        } catch {
            Issue.record("expected DaemonClientError, got \(error)")
        }
    }

    @Test func timesOutOnSilentServer() throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .silence)
        try server.start()
        defer { server.stop() }
        let client = CLIDaemonClient(path: server.path, timeoutSeconds: 1)
        #expect(throws: DaemonClientError.timedOut) {
            try client.roundTrip(.status)
        }
    }

    @Test func rejectsBuildMismatchBeforeDispatch() throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(
            path: dir.socketPath("s.sock"),
            build: "cc-vigil.cli.v2",
            reply: .respond(.ok)
        )
        try server.start()
        defer { server.stop() }
        let client = CLIDaemonClient(path: server.path, timeoutSeconds: 5)
        do {
            _ = try client.roundTrip(.ping)
            Issue.record("expected a build rejection")
        } catch let error as DaemonClientError {
            guard case .rejected = error else {
                Issue.record("expected rejected, got \(error)")
                return
            }
        }
        #expect(server.requests.isEmpty)
    }

    @Test func reportsMalformedReplies() throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let junk = Data(#"{"result":"bogus"}"#.utf8)
        let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .raw(junk))
        try server.start()
        defer { server.stop() }
        let client = CLIDaemonClient(path: server.path, timeoutSeconds: 1)
        do {
            _ = try client.roundTrip(.status)
            Issue.record("expected a malformedReply error")
        } catch let error as DaemonClientError {
            guard case .malformedReply = error else {
                Issue.record("expected malformedReply, got \(error)")
                return
            }
        }
    }

    @Test func rejectsOverlongSocketPaths() {
        let path = "/tmp/" + String(repeating: "x", count: 120) + ".sock"
        let client = CLIDaemonClient(path: path, timeoutSeconds: 1)
        do {
            _ = try client.roundTrip(.ping)
            Issue.record("expected a transport error")
        } catch let error as DaemonClientError {
            guard case .transport = error else {
                Issue.record("expected transport, got \(error)")
                return
            }
        } catch {
            Issue.record("expected transport, got \(error)")
        }
    }
}
