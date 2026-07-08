import CCVigilDaemonKit
import Foundation
import Testing

@Test func deliverRepliesEmptyOnceForNilSnapshot() {
    var replies: [Data] = []
    AppStatusSubscription.deliver(snapshot: nil) { replies.append($0) }
    #expect(replies == [Data()])
}

@Test func deliverRepliesSnapshotOnceWhenPresent() {
    var replies: [Data] = []
    let payload = Data("status".utf8)
    AppStatusSubscription.deliver(snapshot: payload) { replies.append($0) }
    #expect(replies == [payload])
}
