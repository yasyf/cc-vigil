import CCVigilCLIKit
import Testing

@Test func rejectsNegativeLineCount() {
    do {
        _ = try LogCommand.parse(["--lines=-1"])
        Issue.record("expected --lines=-1 to be rejected, not parsed")
    } catch {
        #expect(LogCommand.message(for: error).contains("must be zero or greater"))
    }
}

@Test func acceptsZeroAndPositiveLineCounts() throws {
    let zero = try LogCommand.parse(["--lines=0"])
    #expect(zero.lines == 0)
    let positive = try LogCommand.parse(["--lines=25"])
    #expect(positive.lines == 25)
}
