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
    @Test func roundTripsPing() async throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .respond(.ok))
        try await server.withStarted { () async throws in
            try await withCLIDaemonClient(path: server.path, timeoutSeconds: 2) { client in
                let first = try await client.roundTrip(.ping)
                let second = try await client.roundTrip(.ping)
                #expect(first == .ok)
                #expect(second == .ok)
                #expect(server.requests == [.ping, .ping])
            }
        }
    }

    @Test func roundTripsStatusReport() async throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .respond(.status(sampleReport)))
        try await server.withStarted { () async throws in
            try await withCLIDaemonClient(path: server.path, timeoutSeconds: 2) { client in
                let response = try await client.roundTrip(.status)
                #expect(response == .status(sampleReport))
                #expect(server.requests == [.status])
            }
        }
    }

    @Test func coalescesConcurrentConnectionSetup() async throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .respond(.ok))
        try await server.withStarted { () async throws in
            try await withCLIDaemonClient(path: server.path, timeoutSeconds: 2) { client in
                async let first = client.roundTrip(.ping)
                async let second = client.roundTrip(.ping)
                let firstResponse = try await first
                let secondResponse = try await second
                #expect(firstResponse == .ok)
                #expect(secondResponse == .ok)
                #expect(server.requests == [.ping, .ping])
            }
        }
    }

    @Test func callerCancellationDoesNotPoisonTheSession() async throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(
            path: dir.socketPath("s.sock"),
            reply: .cancellableStatusThenRespond(.ok)
        )
        try await server.withStarted { () async throws in
            try await withCLIDaemonClient(path: server.path, timeoutSeconds: 2) { client in
                let pending = Task { try await client.roundTrip(.status) }
                await server.waitForRequest(.status)
                #expect(server.requests.contains(.status))
                pending.cancel()
                await #expect(throws: CancellationError.self) {
                    try await pending.value
                }
                let response = try await client.roundTrip(.ping)
                #expect(response == .ok)
            }
        }
    }

    @Test func deliversDaemonErrors() async throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(
            path: dir.socketPath("s.sock"),
            reply: .respond(.error(message: "no hold with key k"))
        )
        try await server.withStarted { () async throws in
            try await withCLIDaemonClient(path: server.path, timeoutSeconds: 2) { client in
                let response = try await client.roundTrip(.release(key: "k"))
                #expect(response == .error(message: "no hold with key k"))
                #expect(server.requests == [.release(key: "k")])
            }
        }
    }

    @Test func failsToConnectWithoutServer() async throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        try await withCLIDaemonClient(path: dir.socketPath("missing.sock"), timeoutSeconds: 1) { client in
            do {
                _ = try await client.roundTrip(.ping)
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
    }

    @Test func timesOutOnSilentServer() async throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .silence)
        try await server.withStarted { () async throws in
            try await withCLIDaemonClient(path: server.path, timeoutSeconds: 1) { client in
                _ = await #expect(throws: DaemonClientError.timedOut) {
                    try await client.roundTrip(.status)
                }
            }
        }
    }

    @Test func rejectsBuildMismatchBeforeDispatch() async throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let server = FakeSocketServer(
            path: dir.socketPath("s.sock"),
            build: "cc-vigil.cli.v2",
            reply: .respond(.ok)
        )
        try await server.withStarted {
            try await withCLIDaemonClient(path: server.path, timeoutSeconds: 5) { client in
                do {
                    _ = try await client.roundTrip(.ping)
                    Issue.record("expected a build rejection")
                } catch let error as DaemonClientError {
                    guard case .rejected = error else {
                        Issue.record("expected rejected, got \(error)")
                        return
                    }
                }
                #expect(server.requests.isEmpty)
            }
        }
    }

    @Test func reportsMalformedReplies() async throws {
        let dir = try ShortTempDir(prefix: "sock")
        defer { dir.tearDown() }
        let junk = Data(#"{"result":"bogus"}"#.utf8)
        let server = FakeSocketServer(path: dir.socketPath("s.sock"), reply: .raw(junk))
        try await server.withStarted {
            try await withCLIDaemonClient(path: server.path, timeoutSeconds: 1) { client in
                do {
                    _ = try await client.roundTrip(.status)
                    Issue.record("expected a malformedReply error")
                } catch let error as DaemonClientError {
                    guard case .malformedReply = error else {
                        Issue.record("expected malformedReply, got \(error)")
                        return
                    }
                }
            }
        }
    }

    @Test func rejectsOverlongSocketPaths() async throws {
        let path = "/tmp/" + String(repeating: "x", count: 120) + ".sock"
        try await withCLIDaemonClient(path: path, timeoutSeconds: 1) { client in
            do {
                _ = try await client.roundTrip(.ping)
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
}
