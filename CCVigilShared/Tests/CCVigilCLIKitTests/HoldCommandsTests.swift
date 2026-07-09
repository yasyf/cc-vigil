import CCVigilCLIKit
import CCVigilShared
import Testing

private enum Step: Equatable {
    case emit(String)
    case send
}

@Test func printsHoldKeyBeforeSendingThenPropagatesTimeout() {
    var steps: [Step] = []
    var thrown: (any Error)?
    do {
        try HoldCommand.perform(
            key: "cli-test01",
            reason: "why",
            ttlSeconds: 3600,
            send: { _ in
                steps.append(.send)
                throw SocketClientError.replyTimedOut(afterSeconds: 5)
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
    #expect(thrown as? SocketClientError == .replyTimedOut(afterSeconds: 5))
    #expect(String(describing: thrown!).contains("may still have applied"))
}

@Test func printsHoldKeyBeforeAConfirmedSend() throws {
    var steps: [Step] = []
    try HoldCommand.perform(
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
