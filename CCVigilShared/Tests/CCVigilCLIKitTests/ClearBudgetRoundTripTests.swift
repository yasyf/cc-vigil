import CCVigilCLIKit
import CCVigilShared
import Foundation
import Testing

@Test func clearTimeoutOutrunsTheDefault() {
    #expect(SocketClient.timeout(for: .clear) == ClearBudget.clientSeconds)
    #expect(SocketClient.timeout(for: .clear) > SocketClient.defaultTimeoutSeconds)
    #expect(SocketClient.timeout(for: .status) == SocketClient.defaultTimeoutSeconds)
    #expect(SocketClient.timeout(for: .ping) == SocketClient.defaultTimeoutSeconds)
}

@Test func clearConfirmsWhenTheDaemonRepliesPastTheDefaultTimeout() throws {
    let dir = try ShortTempDir(prefix: "sock")
    defer { dir.tearDown() }
    // A slow pmset makes the daemon confirm the clear only after several seconds;
    // the default 5s client budget would abandon it, so the clear op rides the
    // wider ClearBudget.clientSeconds budget instead.
    let stall = Double(SocketClient.defaultTimeoutSeconds) + 1
    let server = FakeSocketServer(
        path: dir.socketPath("s.sock"),
        reply: .delayedRespond(.ok, afterSeconds: stall)
    )
    try server.start()
    defer { server.stop() }
    let client = SocketClient(path: server.path, timeoutSeconds: SocketClient.timeout(for: .clear))
    #expect(try client.roundTrip(.clear) == .ok)
    #expect(server.requests == [.clear])
}
