import CCVigilShared
import os
import Testing

@Test func firstCallFiresAndReturnsTrue() {
    let delivered = OSAllocatedUnfairLock<[String]>(initialState: [])
    let resume = ResumeOnce<String> { value in delivered.withLock { $0.append(value) } }
    #expect(resume("first") == true)
    #expect(delivered.withLock { $0 } == ["first"])
}

@Test func subsequentCallsAreDropped() {
    let delivered = OSAllocatedUnfairLock<[String]>(initialState: [])
    let resume = ResumeOnce<String> { value in delivered.withLock { $0.append(value) } }
    resume("first")
    #expect(resume("second") == false)
    #expect(resume("third") == false)
    #expect(delivered.withLock { $0 } == ["first"])
}

@Test func concurrentCallersFireExactlyOnce() async {
    let count = OSAllocatedUnfairLock(initialState: 0)
    let resume = ResumeOnce<Int> { _ in count.withLock { $0 += 1 } }
    await withTaskGroup(of: Void.self) { group in
        for value in 0 ..< 64 {
            group.addTask { resume(value) }
        }
    }
    #expect(count.withLock { $0 } == 1)
}
