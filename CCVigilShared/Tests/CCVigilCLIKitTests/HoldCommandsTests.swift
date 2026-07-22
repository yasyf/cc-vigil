import CCVigilCLIKit
import CCVigilShared
import CCVigilTransport
import Testing

private enum Step: Equatable {
    case emit(String)
    case send
}

@Test func printsHoldKeyBeforeSendingThenPropagatesTimeout() async throws {
    var steps: [Step] = []
    var thrown: (any Error)?
    do {
        try await HoldCommand.perform(
            key: "cli-test01",
            reason: "why",
            ttlSeconds: 3600,
            send: { _ in
                steps.append(.send)
                throw DaemonClientError.timedOut
            },
            emit: { steps.append(.emit($0)) }
        )
        Issue.record("expected the timeout to propagate")
    } catch {
        thrown = error
    }
    #expect(steps == [
        .emit("holding cli-test01 for 1h; release with: cc-vigil release cli-test01"),
        .send,
    ])
    #expect(thrown as? DaemonClientError == .timedOut)
    #expect(try String(describing: #require(thrown)) == "daemon request timed out")
}

@Test func printsHoldKeyBeforeAConfirmedSend() async throws {
    var steps: [Step] = []
    try await HoldCommand.perform(
        key: "cli-ok",
        reason: "why",
        ttlSeconds: 60,
        send: { _ in
            steps.append(.send)
            return .ok
        },
        emit: { steps.append(.emit($0)) }
    )
    #expect(steps == [
        .emit("holding cli-ok for 1m; release with: cc-vigil release cli-ok"),
        .send,
    ])
}
