import CCVigilCLIKit
import CCVigilShared
import CCVigilTransport
import Foundation
import Testing

@Test func clearTimeoutOutrunsTheDefault() {
    #expect(CLIDaemonClient.timeout(for: .clear) == ClearBudget.clientSeconds)
    #expect(CLIDaemonClient.timeout(for: .clear) > CLIDaemonClient.defaultTimeoutSeconds)
    #expect(CLIDaemonClient.timeout(for: .status) == CLIDaemonClient.defaultTimeoutSeconds)
    #expect(CLIDaemonClient.timeout(for: .ping) == CLIDaemonClient.defaultTimeoutSeconds)
}

@Test func clearConfirmsWhenTheDaemonRepliesPastTheDefaultTimeout() async throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    // A slow pmset makes the daemon confirm the clear only after several seconds;
    // the default 5s client budget would abandon it, so the clear op rides the
    // wider ClearBudget.clientSeconds budget instead.
    let stall = Double(CLIDaemonClient.defaultTimeoutSeconds) + 1
    let server = FakeSocketServer(
        path: dir.socketPath("s.sock"),
        reply: .delayedRespond(.ok, afterSeconds: stall)
    )
    try await server.withStarted { () async throws in
        try await withCLIDaemonClient(
            path: server.path,
            timeoutSeconds: CLIDaemonClient.timeout(for: .clear)
        ) { client in
            let response = try await client.roundTrip(.clear)
            #expect(response == .ok)
            #expect(server.requests == [.clear])
        }
    }
}
